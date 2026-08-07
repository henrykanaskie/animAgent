#!/usr/bin/env python3
"""Drive an interactive TUI under a real pty.

Usage: ptydrive.py <script.json>

script.json:
{
  "cmd": ["claude"],
  "cwd": "/path",
  "env_clear": ["CLAUDECODE", "..."],
  "env_set": {"TERM": "xterm-256color"},
  "log": "/path/raw.log",
  "hard_timeout": 300,
  "cols": 120, "rows": 40,
  "steps": [
    {"await": "regex", "timeout": 60},
    {"send": "text"},
    {"key": "enter"},
    {"sleep": 5},
    {"note": "free text marker"}
  ]
}

Exits 0 if every step completed, 3 if a step timed out. Always kills the child
and always writes the raw log.
"""
import fcntl
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time

ANSI = re.compile(rb"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b[]P][^\x07\x1b]*(?:\x07|\x1b\\)?|\x1b[()][A-Za-z0-9]|\x1b[=>NOM78]|\r")

KEYS = {
    "enter": b"\r",
    "esc": b"\x1b",
    "ctrl-c": b"\x03",
    "ctrl-d": b"\x04",
    "down": b"\x1b[B",
    "up": b"\x1b[A",
    "tab": b"\t",
    "space": b" ",
    "1": b"1",
    "2": b"2",
    "3": b"3",
    "y": b"y",
    "n": b"n",
}


def strip(b):
    return ANSI.sub(b"", b)


def main():
    spec = json.load(open(sys.argv[1]))
    cols = spec.get("cols", 120)
    rows = spec.get("rows", 40)

    env = dict(os.environ)
    for k in spec.get("env_clear", []):
        env.pop(k, None)
    env.update(spec.get("env_set", {}))

    master, slave = os.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))

    proc = subprocess.Popen(
        spec["cmd"], cwd=spec.get("cwd"), env=env,
        stdin=slave, stdout=slave, stderr=slave,
        preexec_fn=os.setsid, close_fds=True,
    )
    os.close(slave)

    logf = open(spec["log"], "wb")
    buf = bytearray()          # stripped, cumulative
    seen_upto = 0              # match cursor
    started = time.time()
    hard = spec.get("hard_timeout", 300)
    rc = 0

    def pump(deadline):
        """Read until deadline. Returns when deadline passes or child exits."""
        while time.time() < deadline:
            if time.time() - started > hard:
                raise TimeoutError("hard timeout")
            r, _, _ = select.select([master], [], [], 0.2)
            if r:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    return False
                if not chunk:
                    return False
                logf.write(chunk)
                logf.flush()
                buf.extend(strip(chunk))
        return True

    try:
        for i, step in enumerate(spec["steps"]):
            tag = step.get("note", "")
            if "note" in step and len(step) == 1:
                print("[%6.1fs] step %d NOTE %s" % (time.time() - started, i, tag), flush=True)
                continue
            if "await" in step:
                pat = re.compile(step["await"].encode(), re.S)
                to = step.get("timeout", 60)
                end = time.time() + to
                hit = None
                while time.time() < end:
                    m = pat.search(buf, seen_upto)
                    if m:
                        hit = m
                        break
                    if not pump(min(end, time.time() + 0.3)):
                        break
                    m = pat.search(buf, seen_upto)
                    if m:
                        hit = m
                        break
                if not hit:
                    print("[%6.1fs] step %d TIMEOUT awaiting %r" %
                          (time.time() - started, i, step["await"]), flush=True)
                    rc = 3
                    break
                seen_upto = hit.end()
                print("[%6.1fs] step %d matched %r %s" %
                      (time.time() - started, i, step["await"], tag), flush=True)
            if "send" in step:
                os.write(master, step["send"].encode())
                print("[%6.1fs] step %d sent %r %s" %
                      (time.time() - started, i, step["send"][:60], tag), flush=True)
            if "key" in step:
                os.write(master, KEYS[step["key"]])
                print("[%6.1fs] step %d key %s %s" %
                      (time.time() - started, i, step["key"], tag), flush=True)
            if "sleep" in step:
                print("[%6.1fs] step %d sleeping %s %s" %
                      (time.time() - started, i, step["sleep"], tag), flush=True)
                pump(time.time() + step["sleep"])
    except TimeoutError as e:
        print("[%6.1fs] HARD TIMEOUT: %s" % (time.time() - started, e), flush=True)
        rc = 4
    except Exception as e:
        print("[%6.1fs] ERROR %r" % (time.time() - started, e), flush=True)
        rc = 5
    finally:
        # drain a little so trailing output (SessionEnd side effects) lands
        try:
            pump(time.time() + spec.get("drain", 3))
        except Exception:
            pass
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        except Exception:
            pass
        time.sleep(1.0)
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except Exception:
            pass
        proc.wait(timeout=10)
        try:
            pump(time.time() + 1)
        except Exception:
            pass
        logf.close()
        os.close(master)
        open(spec["log"] + ".txt", "wb").write(bytes(buf))
        print("[%6.1fs] done rc=%d  log=%s" % (time.time() - started, rc, spec["log"]), flush=True)
    sys.exit(rc)


if __name__ == "__main__":
    main()
