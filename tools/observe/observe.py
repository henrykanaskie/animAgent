#!/usr/bin/env python3
"""Watch the room the way a user would, and keep the evidence.

    python3 tools/observe/observe.py --out <run-dir>

One command. It drives a real multi-agent Claude Code session, captures every
hook payload it emits, then renders the room that session would have produced —
a frame every couple of seconds at the real panel size — and writes what was
*actually* true beside each frame.

**Why the ground truth has to be there.** `docs/01-PRD.md` S5 is "a cold
observer watching the panel for 15 seconds can correctly say how many agents are
running and whether any are idle." That is not a claim about a picture. It is a
claim about a picture *agreeing with reality*, and a screenshot on its own
cannot be right or wrong about anything. So every frame is written with a
sidecar saying how many agents existed at that instant, what their types were,
which held open calls and which were dormant — read out of the delta stream, not
out of the picture. The judgement about whether the picture communicates it is a
human's; this only makes it answerable.

**What it does to your machine, and what it does not.**

- It never writes `~/.claude/settings.json`. Hooks are installed *project-scoped*
  in a throwaway sandbox and the sandbox's previous settings are restored on the
  way out, whatever happens.
- It never binds port 8787. The maintainer's own app is bound there and their
  live session posts to it; the logger takes an ephemeral port from the kernel
  and refuses to start if it somehow gets 8787.
- It never renders the panel. `spriteroom --render` is offscreen.
  `--panel-render` puts the real panel over whatever you are looking at and is
  not used here, at any point, for any reason.
- Every interactive run is bounded twice: `ptydrive.py`'s own `hard_timeout` and
  an outer `subprocess` timeout with a process-group kill behind it. It ends by
  checking that the port is free and that the capture has stopped growing,
  because an orphaned logger from an earlier capture once survived overnight.

**The app is pinned by default.** `--app-from head` exports the committed tree to
the run directory and builds `spriteroom` there, with the art symlinked in. Two
other agents are live in `Sources/`, and a baseline rendered by a binary that is
being rebuilt underneath it is not a baseline. `--app-from working` uses the
repo's own `.build` instead, when you want to see the working tree.

Python 3 stdlib only.
"""

import argparse
import contextlib
import hashlib
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
PTYDRIVE = os.path.join(REPO, "tools", "pty-capture", "ptydrive.py")
LOGGER = os.path.join(REPO, "tools", "hook-logger", "logger.py")
FILMSTRIP = os.path.join(HERE, "filmstrip.py")

# The maintainer's app is bound here and their live session posts to it. Binding
# it would take their hooks; killing it would take their session.
FORBIDDEN_PORT = 8787

# Every event name the sandbox will report. Same list M0a and M0c captured
# against, so a capture from here is comparable with `fixtures/`.
HOOK_EVENTS = [
    "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
    "PostToolUseFailure", "PostToolBatch", "PermissionRequest", "PermissionDenied",
    "SubagentStart", "SubagentStop", "Stop", "StopFailure", "Notification",
    "PreCompact", "PostCompact", "TaskCreated", "TaskCompleted",
]

# The environment a nested Claude Code inherits and must not: these mark the
# process as already being inside a session and change its behaviour. Same list
# M0c used.
ENV_CLEAR = [
    "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CODE_SESSION_ID",
    "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_BRIDGE_SESSION_ID",
    "CLAUDE_CODE_EXECPATH", "CLAUDE_PID", "CLAUDE_EFFORT", "AI_AGENT",
    "CLAUDE_CODE_SSE_PORT",
]

# Two agent types that do not exist as built-ins, defined in the sandbox so the
# session has more than one kind of worker in it. The *payloads* are still real
# — this decides what the session does, not what the capture says about it.
SANDBOX_AGENTS = {
    "reviewer": """---
name: reviewer
description: Reads a file and reports what is in it. Used by the observe harness.
tools: Read, Bash, Grep
---

Read the file you are given, run the shell command you are given, and reply with
one short line. Do not write anything.
""",
    "archivist": """---
name: archivist
description: Reads a file and files it away. Used by the observe harness.
tools: Read, Bash, Glob
---

Read the file you are given, run the shell command you are given, and reply with
one short line. Do not write anything.
""",
}

# Five subagents, four distinct `agent_type`s, one type used twice — the case
# that breaks anything keyed on the type rather than on `agent_id`. Plus the
# main thread, which is six characters: S4's population.
#
# Staggered waits so the room is never uniformly busy: at most sample instants
# some characters hold an open call and some do not, which is the second half of
# what S5 asks an observer to read off the screen.
#
# **The wait is a Python `time.sleep`, not `sleep(1)`.** A rehearsal found that
# Claude Code refuses a bare foreground `sleep`, and the agents worked around it
# by backgrounding the shell — which closes the `Bash` call immediately and
# leaves every character idle within a second of starting. The capture was real
# and useless: a filmstrip of six characters doing nothing is not a test of
# whether you can tell who is working. `python3 -c` holds the call open for as
# long as it says, verified before this was written.
def wait_command(seconds):
    return 'python3 -c "import time; time.sleep(%d)"' % seconds


DISPATCH = [
    ("general-purpose", "note-1.txt", 40),
    ("general-purpose", "note-2.txt", 70),
    ("Explore", "note-3.txt", 55),
    ("reviewer", "note-4.txt", 85),
    ("archivist", "note-5.txt", 100),
]

PROMPT = (
    "In ONE single message make FIVE Agent tool calls, every one with "
    "run_in_background true so all five run concurrently. "
    + " ".join(
        "Subagent %d: subagent_type %s, read observe-work/%s with Read, then run "
        "exactly this in the foreground with Bash: %s , then reply done."
        % (i + 1, kind, note, wait_command(seconds))
        for i, (kind, note, seconds) in enumerate(DISPATCH))
    + " Every subagent must run its command in the foreground and wait for it; "
      "none of them may background it. After dispatching all five reply only with "
      "DISPATCHED. Do not wait for them and do not use any other tool."
)


def log(message):
    print("[observe] %s" % message, flush=True)


def free_port():
    with contextlib.closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    if port == FORBIDDEN_PORT:
        raise RuntimeError("the kernel handed out %d, which is the maintainer's app"
                           % FORBIDDEN_PORT)
    return port


def port_is_free(port):
    with contextlib.closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        try:
            s.connect(("127.0.0.1", port))
            return False
        except OSError:
            return True


def hook_settings(port):
    url = "http://127.0.0.1:%d/hook" % port
    entry = {"matcher": "*", "hooks": [{"type": "http", "url": url, "timeout": 2}]}
    return {"hooks": {name: [json.loads(json.dumps(entry))] for name in HOOK_EVENTS}}


def sha256(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


# ------------------------------------------------------------------- the app

def pin_app(out, source):
    """Build `spriteroom` from the committed tree, art symlinked in.

    The working tree is being edited by other agents while this runs. A frame
    rendered by a binary that changed halfway through the filmstrip is evidence
    of nothing, so the baseline gets its own copy of the app and its own build
    directory."""
    app = os.path.join(out, "app")
    if source == "working":
        binaries = (os.path.join(REPO, ".build/debug/spriteroom"),
                    os.path.join(REPO, ".build/debug/spriteroom-replay"))
        for b in binaries:
            if not os.path.exists(b):
                raise RuntimeError("no %s — run `swift build` first" % b)
        head = subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        return binaries, {"source": "working tree .build", "head": head,
                          "dirty": True}

    head = subprocess.run(["git", "-C", REPO, "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()
    if not os.path.exists(os.path.join(app, "Package.swift")):
        log("exporting %s to %s" % (head[:12], app))
        os.makedirs(app, exist_ok=True)
        archive = subprocess.Popen(["git", "-C", REPO, "archive", "HEAD"],
                                   stdout=subprocess.PIPE)
        subprocess.run(["tar", "-x", "-C", app], stdin=archive.stdout, check=True)
        archive.wait()
        # `assets/` is not redistributable and so is not in the history apart
        # from its manifest. The manifest comes from the commit; the art is
        # linked from the working copy, because there is nowhere else it exists.
        for name in sorted(os.listdir(os.path.join(REPO, "assets"))):
            if name == "manifest.json":
                continue
            link = os.path.join(app, "assets", name)
            if not os.path.lexists(link):
                os.symlink(os.path.join(REPO, "assets", name), link)
    for product in ("spriteroom", "spriteroom-replay"):
        log("building %s at %s" % (product, head[:12]))
        subprocess.run(["swift", "build", "--product", product, "-c", "debug"],
                       cwd=app, check=True, capture_output=True, text=True, timeout=1800)
    binaries = (os.path.join(app, ".build/debug/spriteroom"),
                os.path.join(app, ".build/debug/spriteroom-replay"))
    return binaries, {"source": "git archive HEAD, built in the run directory",
                      "head": head, "dirty": False}


# --------------------------------------------------------------- the session

class Sandbox:
    """Project-scoped hooks in a throwaway directory, put back afterwards."""

    def __init__(self, path, port, out):
        self.path = path
        self.port = port
        self.out = out
        self.settings = os.path.join(path, ".claude", "settings.json")
        self.backup = os.path.join(out, "sandbox-settings.orig.json")
        self.had_settings = False
        self.wrote_agents = []
        self.work = os.path.join(path, "observe-work")

    def __enter__(self):
        os.makedirs(os.path.dirname(self.settings), exist_ok=True)
        if os.path.exists(self.settings):
            shutil.copy2(self.settings, self.backup)
            self.had_settings = True
        json.dump(hook_settings(self.port), open(self.settings, "w"), indent=1)

        agents_dir = os.path.join(self.path, ".claude", "agents")
        os.makedirs(agents_dir, exist_ok=True)
        for name, body in SANDBOX_AGENTS.items():
            target = os.path.join(agents_dir, name + ".md")
            if not os.path.exists(target):
                open(target, "w").write(body)
                self.wrote_agents.append(target)

        os.makedirs(self.work, exist_ok=True)
        for i in range(1, len(DISPATCH) + 1):
            open(os.path.join(self.work, "note-%d.txt" % i), "w").write(
                "note %d\nthis file exists so a subagent has something real to Read\n" % i)
        return self

    def __exit__(self, *_):
        # Put the sandbox back the way it was, including on the failure paths.
        # It is a scratch directory, but it is also M0c's evidence.
        try:
            if self.had_settings:
                shutil.copy2(self.backup, self.settings)
            elif os.path.exists(self.settings):
                os.remove(self.settings)
        except OSError as e:
            log("could not restore %s: %s" % (self.settings, e))
        for target in self.wrote_agents:
            with contextlib.suppress(OSError):
                os.remove(target)
        with contextlib.suppress(OSError):
            os.rmdir(os.path.join(self.path, ".claude", "agents"))
        shutil.rmtree(self.work, ignore_errors=True)
        return False


def start_logger(port, out):
    handle = open(os.path.join(out, "logger.log"), "w")
    proc = subprocess.Popen(
        [sys.executable, LOGGER, "--port", str(port), "--out", out, "--scenario", "capture"],
        stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
    for _ in range(50):
        try:
            urllib.request.urlopen(
                "http://127.0.0.1:%d/control/scenario?name=capture" % port, timeout=1).read()
            log("logger up on 127.0.0.1:%d (pid %d)" % (port, proc.pid))
            return proc, handle
        except Exception:
            if proc.poll() is not None:
                raise RuntimeError("logger exited immediately; see logger.log")
            time.sleep(0.2)
    raise RuntimeError("logger did not answer on port %d" % port)


def stop_logger(proc, handle, port):
    """Leave no bound port. An orphaned logger from an earlier capture survived
    from one day to the next here, so this is deliberately belt and braces."""
    if proc.poll() is None:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            with contextlib.suppress(ProcessLookupError):
                os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
            proc.wait(timeout=5)
    handle.close()
    for _ in range(25):
        if port_is_free(port):
            log("logger stopped, port %d released" % port)
            return True
        time.sleep(0.2)
    log("WARNING: port %d is still bound after stopping the logger" % port)
    return False


def drive(out, sandbox, claude, dwell):
    """One interactive session under a pty. Bounded twice."""
    raw = os.path.join(out, "session.raw")
    spec = {
        "cmd": [claude, "--dangerously-skip-permissions"],
        "cwd": sandbox,
        "env_clear": ENV_CLEAR,
        "env_set": {"TERM": "xterm-256color", "COLUMNS": "120", "LINES": "40"},
        "log": raw,
        "hard_timeout": dwell + 180,
        "drain": 6,
        "cols": 120, "rows": 40,
        "steps": [
            {"await": "BypassPermissions|Yes,Iaccept|forshortcuts|Try\\s*\"|Welcometo",
             "timeout": 90, "note": "startup"},
            {"sleep": 2},
            {"key": "2", "note": "accept bypass permissions if it asked"},
            {"sleep": 2},
            {"key": "enter"},
            {"sleep": 6},
            {"await": "forshortcuts|Try\\s*\"|Welcometo|>", "timeout": 60, "note": "tui ready"},
            {"sleep": 2},
            {"send": PROMPT},
            {"sleep": 3},
            {"key": "enter", "note": "submit"},
            {"sleep": dwell, "note": "let the five run"},
            {"send": "/exit"},
            {"sleep": 2},
            {"key": "enter"},
            # If anything is still in flight, `/exit` raises a confirmation
            # ("Background work is running — 1. Exit anyway"). The rehearsal left
            # it unanswered and the session never emitted `SessionEnd`, so the
            # capture ended with calls open that nothing ever closed. A second
            # `enter` takes the default. With no dialog it submits an empty
            # prompt, which is harmless.
            {"sleep": 3},
            {"key": "enter", "note": "confirm exit if it asked"},
            {"sleep": 12, "note": "let SessionEnd land"},
        ],
    }
    spec_path = os.path.join(out, "session.json")
    json.dump(spec, open(spec_path, "w"), indent=1)

    log("driving a session in %s (dwell %ds)" % (sandbox, dwell))
    handle = open(os.path.join(out, "ptydrive.log"), "w")
    proc = subprocess.Popen([sys.executable, PTYDRIVE, spec_path],
                            stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
    try:
        rc = proc.wait(timeout=spec["hard_timeout"] + 120)
    except subprocess.TimeoutExpired:
        log("ptydrive overran its own hard timeout; killing its process group")
        with contextlib.suppress(ProcessLookupError):
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        rc = proc.wait(timeout=30)
    handle.close()
    log("ptydrive exited rc=%d" % rc)
    return rc


def classify_exit(out, capture, rc):
    """Say what the session's exit actually was, rather than trusting `rc`.

    `ptydrive.py` writes the confirm keystroke unconditionally, and when nothing
    was left in flight the TUI has already gone by then, so the write lands on a
    closed pty and the rig reports `rc=5`. That is the *good* path — the session
    exited on the first `enter` and `SessionEnd` is in the capture. The rig is
    M0c's and is left alone; the classification happens here instead of
    pretending the return code said something it did not."""
    log_path = os.path.join(out, "ptydrive.log")
    text = open(log_path).read() if os.path.exists(log_path) else ""
    ended = False
    if os.path.exists(capture):
        for line in open(capture):
            if '"SessionEnd"' in line:
                ended = True
    if rc == 0:
        return "clean" if ended else "driver finished, but no SessionEnd was captured"
    if rc == 5 and "Input/output error" in text and ended:
        return "clean; the pty closed before the confirm keystroke (rc=5 is that write)"
    if rc == 3:
        return "a step timed out — see ptydrive.log"
    if rc == 4:
        return "the driver hit its own hard timeout"
    return "rc=%d, SessionEnd %s" % (rc, "captured" if ended else "missing")


def capture_is_quiet(path, seconds=6):
    """Nothing is still posting. A session that outlived the driver would keep
    appending here, and that is the shape an orphan takes."""
    before = os.path.getsize(path) if os.path.exists(path) else 0
    time.sleep(seconds)
    after = os.path.getsize(path) if os.path.exists(path) else 0
    if after != before:
        log("WARNING: the capture grew by %d bytes after the session ended — "
            "something is still running" % (after - before))
        return False
    return True


# ---------------------------------------------------------------------- main

def default_out():
    scratch = os.environ.get("CLAUDE_SCRATCHPAD")
    if scratch:
        return os.path.join(scratch, "observe", "baseline")
    return os.path.join(REPO, ".observe", "baseline")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=default_out(), help="run directory")
    ap.add_argument("--sandbox", default=None,
                    help="throwaway project to run the session in; default is the "
                         "M0c capture sandbox beside the run directory")
    ap.add_argument("--claude", default=shutil.which("claude") or "claude")
    ap.add_argument("--dwell", type=int, default=170,
                    help="seconds to let the dispatched agents run")
    ap.add_argument("--interval", type=float, default=1.5, help="seconds between frames")
    ap.add_argument("--size", default="720x400", help="viewport; 720x400 is the real panel")
    ap.add_argument("--app-from", choices=("head", "working"), default="head")
    ap.add_argument("--capture-only", action="store_true", help="drive the session, no frames")
    ap.add_argument("--frames-only", action="store_true",
                    help="skip the session; re-render an existing capture.jsonl")
    args = ap.parse_args()

    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    capture = os.path.join(out, "capture.jsonl")
    sandbox = args.sandbox or os.path.join(os.path.dirname(os.path.dirname(out)), "m0-capture")

    (spriteroom, replay), app_info = pin_app(out, args.app_from)
    # `--frames-only` re-analyses a run that already happened. Its metadata —
    # the port, how the session exited, whether the port came back — is evidence
    # about that run and must survive a re-render, so this merges rather than
    # starts a new file.
    run_json = os.path.join(out, "run.json")
    meta = json.load(open(run_json)) if os.path.exists(run_json) else {}
    meta.update({
        "started": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "app": dict(app_info, spriteroom_sha256=sha256(spriteroom),
                    replay_sha256=sha256(replay)),
        "manifest_sha256": sha256(os.path.join(REPO, "assets", "manifest.json")),
        "sandbox": sandbox,
        "dispatch": [{"agent_type": k, "reads": n, "sleeps": s} for k, n, s in DISPATCH],
    })

    if not args.frames_only:
        if os.path.exists(capture):
            os.remove(capture)
        if not os.path.isdir(sandbox):
            raise SystemExit("no sandbox at %s — pass --sandbox" % sandbox)
        version = subprocess.run([args.claude, "--version"], capture_output=True,
                                 text=True).stdout.strip()
        port = free_port()
        meta.update({"claude_version": version, "port": port})
        log("claude %s, logger port %d (never %d)" % (version, port, FORBIDDEN_PORT))

        proc = handle = None
        started = time.time()
        try:
            with Sandbox(sandbox, port, out):
                proc, handle = start_logger(port, out)
                meta["ptydrive_rc"] = drive(out, sandbox, args.claude, args.dwell)
        finally:
            if proc is not None:
                meta["port_released"] = stop_logger(proc, handle, port)
        meta["session_seconds"] = round(time.time() - started, 1)
        meta["session_exit"] = classify_exit(out, capture, meta.get("ptydrive_rc", -1))
        meta["quiet_after_teardown"] = capture_is_quiet(capture)
        log("session exit: %s" % meta["session_exit"])

    if not os.path.exists(capture):
        raise SystemExit("no capture at %s" % capture)
    lines = sum(1 for l in open(capture) if l.strip())
    meta["events_captured"] = lines
    log("captured %d events into %s" % (lines, capture))
    json.dump(meta, open(os.path.join(out, "run.json"), "w"), indent=2)

    if args.capture_only:
        return 0

    log("rendering the filmstrip and its ground truth")
    rc = subprocess.run(
        [sys.executable, FILMSTRIP, "--capture", capture, "--out", out,
         "--interval", str(args.interval), "--size", args.size,
         "--spriteroom", spriteroom, "--replay", replay],
        cwd=REPO).returncode
    meta["filmstrip_rc"] = rc
    json.dump(meta, open(os.path.join(out, "run.json"), "w"), indent=2)
    return rc


if __name__ == "__main__":
    sys.exit(main())
