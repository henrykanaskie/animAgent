#!/usr/bin/env python3
"""Turn a captured hook stream into a filmstrip with ground truth beside it.

    python3 tools/observe/filmstrip.py --capture RUN/capture.jsonl --out RUN

S5 is "a cold observer watching the panel for 15 seconds can correctly say how
many agents are running and whether any are idle." That is a claim about
*agreement between a picture and reality*, so a picture on its own cannot answer
it and neither can a delta log. This produces both, sampled on the same clock,
with the same origin, so they can be laid side by side:

  frames/<name>-t012.00.png    what the room drew at fixture second 12
  frames/<name>-t012.00.json   what was actually true at fixture second 12

**Three independent sources, deliberately.**

1. `spriteroom-replay` → the delta stream. This is *reality*: the `WorldModel`'s
   reading of the captured payloads. Folded forward to each sample it gives the
   agent set, each agent's type, each agent's open-call set, and dormancy.
2. `spriteroom --render` with `SPRITEROOM_DEBUG=1` → the scene's own roster at
   the sample instant, printed by `RoomScene.debugRoster`. This is what the
   thing that drew the picture believes it drew, after animation, and it comes
   out of a different code path from (1): `SceneDirector` and `RoomScene`, not
   `WorldModel`.
3. The same trace's timestamped `SpriteIntent` lines → a reconstruction of what
   the director *told* the scene. It carries two facts the roster string does
   not print at all: the badge's `isDormant` flag and its open-call count.

4. The PNGs themselves, decoded. Frame-to-frame change, and a short second
   render `--motion-probe` seconds after each mark, because "whether any are
   idle" is a thing an observer reads off *motion* and two frames 1.5 s apart
   come out pixel-identical about half the time even with five characters
   working: the ambient loop lands on the same phase. Identity between
   consecutive filmstrip frames is therefore not evidence of a static room, and
   the probe is what separates them.

(1) versus (2)/(3) is the only mechanical check available on "does the picture
match reality". It is not a check on whether the picture is legible: nothing
here can be, and this file does not try. It reports counts and names.

**What it cannot answer, said plainly.** Whether the six characters are
*distinguishable*, whether the nameplate can be read at this size, whether a
badge means anything to someone who has not read the source: every one of those
is the S5 judgement and needs an eye. It can say two characters wear the same
sprite variant; it cannot say two characters look the same. It also never sees
the real panel: the notch reveal, the drop animation, the retract, and whatever
the panel's own compositing does to these pixels are all outside `--render`.

**The renderer is deterministic**, verified: rendering mark t in its own process
produces the same bytes as rendering it inside a longer run of marks. That is
what makes the per-frame roster runs legitimate: each frame's roster is read
from the same simulation that drew that frame.

Nothing here opens a window. `--render` is offscreen; `--panel-render` would put
the real panel over the user's screen and is never used.

Python 3 stdlib only.
"""

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import zlib
from datetime import datetime

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# ---------------------------------------------------------------- delta stream

DELTA_LINE = re.compile(r"^\s*\[\s*(-?[\d.]+)\]\s+(\w+)\s*(.*?)\s*$")
CALL_TAIL = re.compile(r"^(?P<ref>\S+)\s+(?P<tool>.+?)\((?P<id>[^()]*)\)(?:\s+(?P<extra>\S+))?$")
APPEARED = re.compile(r"^(?P<ref>\S+)\s+type=(?P<type>.*?)\s+(?P<lifecycle>\w+)$")


def parse_deltas(text):
    """[(t, kind, payload_dict), ...] in stream order."""
    out = []
    for line in text.splitlines():
        m = DELTA_LINE.match(line)
        if not m:
            continue
        t, kind, rest = float(m.group(1)), m.group(2), m.group(3)
        if kind == "agentAppeared":
            a = APPEARED.match(rest)
            if not a:
                continue
            out.append((t, kind, {"ref": a.group("ref"),
                                  "type": None if a.group("type") == "-" else a.group("type"),
                                  "lifecycle": a.group("lifecycle")}))
        elif kind in ("agentDeparted", "reportDelivered"):
            out.append((t, kind, {"ref": rest.split()[0]}))
        elif kind == "agentLinked":
            ref, _, parent = rest.partition(" parent=")
            out.append((t, kind, {"ref": ref.strip(), "parent": parent.strip()}))
        elif kind in ("callOpened", "callClosed", "callAbandoned"):
            c = CALL_TAIL.match(rest)
            if not c:
                continue
            out.append((t, kind, {"ref": c.group("ref"), "tool": c.group("tool"),
                                  "id": c.group("id"), "extra": c.group("extra")}))
        elif kind == "dormancyChanged":
            ref, _, word = rest.rpartition(" ")
            out.append((t, kind, {"ref": ref.strip(), "dormant": word.strip() == "dormant"}))
        elif kind == "attentionChanged":
            ref, _, word = rest.partition(" ")
            out.append((t, kind, {"ref": ref.strip(),
                                  "attention": None if word.strip() == "cleared" else word.strip()}))
        elif kind == "populationChanged":
            leaf, _, count = rest.rpartition("=")
            out.append((t, kind, {"project": leaf, "count": int(count)}))
    return out


STEP = 1.0 / 60.0


def render_instants(mark, step=STEP):
    """`(when the PNG was drawn, when the roster was printed)`, in fixture seconds.

    Both are read off `renderOffscreen`'s own loop rather than assumed, because
    the two are **not the same instant** and the difference is one 60 Hz tick:

        while time <= last + step {        // `last` is the final mark
            ingest every event up to time
            apply, advance, render
            write any mark <= time         // ← the PNG
            time += step
        }
        print debugRoster                  // ← after the loop, one tick later

    So the roster describes a world the picture does not yet show. Folding the
    deltas to one instant and comparing it against both produced two
    "disagreements" on the first baseline run, and both were this, not the app:
    a `Read` that opened and closed inside 10 ms, landing between the frame and
    the roster.

    The accumulation is reproduced step by step rather than computed as
    `ceil(mark*60)/60` for the same reason: repeated `+= 1/60` in a double
    drifts, and `31.5` comes out as `31.499999999999492`, which is on the other
    side of the comparison the renderer actually makes."""
    time, frame_at = 0.0, None
    while time <= mark + step:
        if frame_at is None and mark <= time + 1e-9:
            frame_at = time
        last_time = time
        time += step
    return (mark if frame_at is None else frame_at), last_time


# The intent trace prints `t` to three decimals, so a comparison against an
# exact 1/60 boundary has to allow for the rounding.
PRINT_EPS = 1e-3


def truth_at(deltas, t):
    """Fold the delta stream forward to fixture second `t`. This is reality."""
    agents = {}
    population = None
    for when, kind, p in deltas:
        if when > t + PRINT_EPS:
            break
        ref = p.get("ref")
        if kind == "agentAppeared":
            a = agents.setdefault(ref, {"ref": ref, "type": None, "open_calls": {},
                                        "dormant": False, "attention": None, "parent": None})
            if p["type"] is not None:
                a["type"] = p["type"]
        elif kind == "agentDeparted":
            agents.pop(ref, None)
        elif kind == "agentLinked":
            if ref in agents:
                agents[ref]["parent"] = p["parent"]
        elif kind == "callOpened":
            if ref in agents:
                agents[ref]["open_calls"][p["id"]] = p["tool"]
        elif kind in ("callClosed", "callAbandoned"):
            if ref in agents:
                agents[ref]["open_calls"].pop(p["id"], None)
        elif kind == "dormancyChanged":
            if ref in agents:
                agents[ref]["dormant"] = p["dormant"]
        elif kind == "attentionChanged":
            if ref in agents:
                agents[ref]["attention"] = p["attention"]
        elif kind == "populationChanged":
            population = p["count"]

    rows = []
    for ref in sorted(agents):
        a = agents[ref]
        rows.append({
            "ref": ref,
            "agent_type": a["type"],
            "is_main": ref.endswith("/main"),
            "open_calls": sorted(a["open_calls"].values()),
            "open_call_count": len(a["open_calls"]),
            "working": len(a["open_calls"]) > 0,
            "dormant": a["dormant"],
            "attention": a["attention"],
            "parent": a["parent"],
        })
    return {
        "agents": rows,
        "agent_count": len(rows),
        "working_count": sum(1 for r in rows if r["working"]),
        "idle_count": sum(1 for r in rows if not r["working"]),
        "dormant_count": sum(1 for r in rows if r["dormant"]),
        "agent_types": sorted({r["agent_type"] or "(main)" for r in rows}),
        "population_delta_said": population,
    }


# ------------------------------------------------------------- render / scene

INTENT_LINE = re.compile(r"^\s*t=\s*(-?[\d.]+)\s+(.*)$")
ROSTER_CHAR = re.compile(r"^\s*roster:\s+(?P<ref>\S+)\s+at x=(?P<x>-?\d+)\s+state=(?P<state>\S+)\s+badge=(?P<badge>\S+)\s*$")
ROSTER_CAMERA = re.compile(r"^\s*roster:\s+camera x=(-?\d+) y=(-?\d+) scale=(\d+) sceneSize=(\d+)x(\d+)\s*$")
WROTE = re.compile(r"^\s{2}(\S+\.png)\s*$")
ROOM = re.compile(r"^room:\s+(\S+)")
# A tool the badge map has no icon for. The room draws the character working
# with no badge, so the picture is short one fact the payload carried.
UNMAPPED = re.compile(r"^unmapped tools:\s+(.*)$")

# `spawnCharacter` has grown fields over time (`station`, `costume`), so the
# tail is matched loosely on purpose: a harness that stops parsing the trace
# because the scene gained a field reports "no characters" rather than an error,
# which is the worst way for a check to fail. Everything after `seat:` is
# optional and captured when present.
SPAWN = re.compile(
    r'spawnCharacter\(agent: (?P<ref>[^,]+), variant: "(?P<variant>[^"]*)", '
    r'nameplate: [^(]*\(lead: "(?P<lead>[^"]*)", role: (?P<role>Optional\("[^"]*"\)|nil)\), '
    r'seat: (?P<seat>\d+)(?P<tail>[^)]*(?:\([^)]*\))?[^)]*)\)')
STATION = re.compile(r'station: (?:"(?P<name>[^"]*)"|nil)')
COSTUME = re.compile(r'costume: (?P<costume>Optional\("[^"]*"\)|nil)')
SETBODY = re.compile(
    r'setBody\(agent: (?P<ref>[^,]+), state: \S*BodyState\.(?P<state>\w+), '
    r'facing: \S*Facing\.(?P<facing>\w+)\)')
SETBADGE = re.compile(
    r'setBadge\(agent: (?P<ref>[^,]+), selection: \S*BadgeSelection\('
    r'badge: (?P<badge>Optional\(\S*ToolBadge\.\w+\)|nil), count: (?P<count>\d+), '
    r'attention: (?P<attention>Optional\([^)]*\)|nil), isDormant: (?P<dormant>true|false)\)\)')
DELIVER = re.compile(r'deliverReport\(agent: (?P<ref>[^,]+), anchorSeat: (?P<seat>\d+)\)')
EXIT = re.compile(r'exitCharacter\(agent: (?P<ref>[^,]+), style: (?P<style>[^)]*\)?)\)')
SCALE = re.compile(r'setScale\((?P<scale>\d+)\)')

OPTIONAL_STR = re.compile(r'Optional\("([^"]*)"\)')
OPTIONAL_ANY = re.compile(r'Optional\((?:\S*ToolBadge\.)?([^)"]*)\)')


def _unopt(text):
    if text == "nil":
        return None
    m = OPTIONAL_STR.match(text) or OPTIONAL_ANY.match(text)
    return m.group(1) if m else text


def parse_intents(text):
    """[(t, [intent_string, ...]), ...] from a SPRITEROOM_DEBUG=1 render."""
    out = []
    for line in text.splitlines():
        m = INTENT_LINE.match(line)
        if m:
            out.append((float(m.group(1)), [s.strip() for s in m.group(2).split(" | ")]))
    return out


def intents_at(intents, t):
    """What the director had told the scene by fixture second `t`."""
    chars = {}
    scale = None
    for when, batch in intents:
        if when > t + PRINT_EPS:
            break
        for one in batch:
            m = SPAWN.search(one)
            if m:
                tail = m.group("tail") or ""
                station = STATION.search(tail)
                costume = COSTUME.search(tail)
                chars[m.group("ref")] = {
                    "ref": m.group("ref"), "variant": m.group("variant"),
                    "nameplate_lead": m.group("lead"),
                    "nameplate_role": _unopt(m.group("role")),
                    "seat": int(m.group("seat")),
                    "station": station.group("name") if station else None,
                    "costume": _unopt(costume.group("costume")) if costume else None,
                    "body": None,
                    "badge": None, "badge_count": 0,
                    "badge_attention": None, "badge_dormant": False,
                    "reports_delivered": 0,
                }
                continue
            m = SETBODY.search(one)
            if m and m.group("ref") in chars:
                chars[m.group("ref")]["body"] = m.group("state")
                continue
            m = SETBADGE.search(one)
            if m and m.group("ref") in chars:
                c = chars[m.group("ref")]
                c["badge"] = _unopt(m.group("badge"))
                c["badge_count"] = int(m.group("count"))
                c["badge_attention"] = _unopt(m.group("attention"))
                c["badge_dormant"] = m.group("dormant") == "true"
                continue
            m = DELIVER.search(one)
            if m and m.group("ref") in chars:
                chars[m.group("ref")]["reports_delivered"] += 1
                continue
            m = EXIT.search(one)
            if m:
                chars.pop(m.group("ref"), None)
                continue
            m = SCALE.search(one)
            if m:
                scale = int(m.group("scale"))
    return {"characters": {k: chars[k] for k in sorted(chars)}, "scale": scale}


def parse_roster(text):
    """The scene's own state at the end of a render: `RoomScene.debugRoster`."""
    chars, camera = {}, None
    for line in text.splitlines():
        m = ROSTER_CHAR.match(line)
        if m:
            chars[m.group("ref")] = {"ref": m.group("ref"), "x": int(m.group("x")),
                                     "state": m.group("state"),
                                     "badge": None if m.group("badge") == "-" else m.group("badge")}
            continue
        m = ROSTER_CAMERA.match(line)
        if m:
            camera = {"x": int(m.group(1)), "y": int(m.group(2)), "scale": int(m.group(3)),
                      "scene_width": int(m.group(4)), "scene_height": int(m.group(5))}
    return {"characters": {k: chars[k] for k in sorted(chars)}, "camera": camera}


def render(spriteroom, capture, outdir, size, marks, theme=None):
    args = [spriteroom, capture, "--render", outdir,
            "--size", "%dx%d" % size, "--at", ",".join("%g" % m for m in marks)]
    if theme:
        args += ["--theme", theme]
    env = dict(os.environ, SPRITEROOM_DEBUG="1")
    p = subprocess.run(args, capture_output=True, text=True, env=env, cwd=REPO, timeout=600)
    if p.returncode != 0:
        raise RuntimeError("render failed (%d):\n%s\n%s" % (p.returncode, p.stdout, p.stderr))
    written = [m.group(1) for m in (WROTE.match(l) for l in p.stdout.splitlines()) if m]
    room, unmapped = None, []
    for line in p.stdout.splitlines():
        m = ROOM.match(line)
        if m:
            room = m.group(1)
        m = UNMAPPED.match(line)
        if m and m.group(1).strip() != "none":
            unmapped = [s.strip() for s in m.group(1).split(",")]
    return p.stdout, written, room, unmapped


# ------------------------------------------------------------------ png pixels

def decode_rgba(path):
    """Minimal PNG reader: 8-bit RGBA, non-interlaced. That is what the
    offscreen renderer writes; anything else raises rather than guessing."""
    raw = open(path, "rb").read()
    assert raw[:8] == b"\x89PNG\r\n\x1a\n", path
    off, idat, hdr = 8, [], None
    while off < len(raw):
        (length,) = struct.unpack(">I", raw[off:off + 4])
        kind = raw[off + 4:off + 8]
        body = raw[off + 8:off + 8 + length]
        if kind == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
        off += 12 + length
    w, h, depth, colour, _, _, interlace = hdr
    if (depth, colour, interlace) != (8, 6, 0):
        raise RuntimeError("unexpected PNG shape %r in %s" % (hdr, path))
    data = zlib.decompress(b"".join(idat))
    bpp, stride = 4, w * 4
    out = bytearray(h * stride)
    prev = bytearray(stride)
    pos = 0
    for y in range(h):
        f = data[pos]
        pos += 1
        line = bytearray(data[pos:pos + stride])
        pos += stride
        if f == 1:
            for i in range(bpp, stride):
                line[i] = (line[i] + line[i - bpp]) & 0xFF
        elif f == 2:
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif f == 3:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 0xFF
        elif f == 4:
            for i in range(stride):
                a = line[i - bpp] if i >= bpp else 0
                c = prev[i - bpp] if i >= bpp else 0
                b = prev[i]
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif f != 0:
            raise RuntimeError("bad filter %d" % f)
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return w, h, bytes(out)


def changed_fraction(a, b):
    if a is None or b is None or len(a[2]) != len(b[2]):
        return None
    pa, pb = a[2], b[2]
    changed = sum(1 for i in range(0, len(pa), 4) if pa[i:i + 4] != pb[i:i + 4])
    return changed / (len(pa) // 4)


# ------------------------------------------------------------------ comparison

ANIMATING = {"walk", "deliver", "spawn", "depart"}


def compare(roster_truth, truth, roster, intents):
    """Mechanical disagreements only. Nothing here judges how it looks.

    `roster_truth` is reality at the instant the roster describes; `truth` is
    reality at the instant the frame was drawn. They are one 60 Hz tick apart
    and each half of the comparison is held to its own, so that a tool call that
    opens and closes between the two is not reported as the room lying. See
    `render_instants`: the first baseline run produced exactly two such
    "disagreements" and both were this."""
    findings = []
    truth_refs = {a["ref"] for a in roster_truth["agents"]}
    scene_refs = set(roster["characters"])
    intent_refs = set(intents["characters"])

    if len(scene_refs) != len(truth_refs):
        findings.append({
            "kind": "population-mismatch",
            "detail": "scene drew %d character(s), the deltas say %d agent(s) exist"
                      % (len(scene_refs), len(truth_refs)),
            "scene": sorted(scene_refs), "truth": sorted(truth_refs)})
    for ref in sorted(scene_refs - truth_refs):
        findings.append({"kind": "ghost-character", "ref": ref,
                         "detail": "on screen, but the deltas say it does not exist "
                                   "(never appeared, or already departed)"})
    for ref in sorted(truth_refs - scene_refs):
        findings.append({"kind": "missing-character", "ref": ref,
                         "detail": "the deltas say this agent exists; nothing is drawn for it"})
    if scene_refs != intent_refs:
        findings.append({"kind": "roster-intent-mismatch",
                         "detail": "the scene's roster and the director's intents disagree "
                                   "about who is in the room",
                         "roster": sorted(scene_refs), "intents": sorted(intent_refs)})

    by_ref = {a["ref"]: a for a in roster_truth["agents"]}
    frame_by_ref = {a["ref"]: a for a in truth["agents"]}
    for ref in sorted(scene_refs & truth_refs):
        t = by_ref[ref]
        state = roster["characters"][ref]["state"]
        if state not in ANIMATING:
            if t["working"] and state != "working":
                findings.append({"kind": "state-mismatch", "ref": ref,
                                 "detail": "holds %d open call(s) %s, drawn '%s'"
                                           % (t["open_call_count"], t["open_calls"], state)})
            if not t["working"] and state == "working":
                findings.append({"kind": "state-mismatch", "ref": ref,
                                 "detail": "holds no open call, drawn 'working'"})
        # The intents were folded to the frame's instant, so they are compared
        # against the frame's truth, not the roster's.
        c = intents["characters"].get(ref)
        f = frame_by_ref.get(ref)
        if c and f:
            if c["badge_dormant"] != f["dormant"]:
                findings.append({"kind": "dormancy-mismatch", "ref": ref,
                                 "detail": "badge isDormant=%s, deltas say dormant=%s"
                                           % (c["badge_dormant"], f["dormant"])})
            if c["badge_count"] != f["open_call_count"]:
                findings.append({"kind": "badge-count-mismatch", "ref": ref,
                                 "detail": "badge count=%d, open calls=%d"
                                           % (c["badge_count"], f["open_call_count"])})
            plate = c["nameplate_role"]
            if (plate or None) != (f["agent_type"] or None) and not f["is_main"]:
                findings.append({"kind": "type-mismatch", "ref": ref,
                                 "detail": "nameplate says %r, the payload's agent_type is %r"
                                           % (plate, f["agent_type"])})
    return findings


def observations(truth, roster, intents):
    """Facts about the frame that are not disagreements. Counting, not judging.

    `variant` is the sprite sheet a character wears. Two characters sharing one
    is not a bug (nothing promises uniqueness) but it is the mechanical form
    of 'they all look the same', so it is counted rather than described."""
    chars = list(intents["characters"].values())
    variants = [c["variant"] for c in chars]
    plates = [(c["nameplate_lead"], c["nameplate_role"]) for c in chars]
    dupes = sorted({v for v in variants if variants.count(v) > 1})
    stations = [c.get("station") for c in chars]
    costumes = [c.get("costume") for c in chars]
    return {
        "characters_drawn": len(chars),
        "distinct_variants": len(set(variants)),
        "shared_variants": dupes,
        "distinct_nameplates": len(set(plates)),
        "distinct_stations": len(set(stations)),
        "stations": sorted({s for s in stations if s}),
        "distinct_costumes": len({c for c in costumes if c}),
        "distinct_seats": len({c["seat"] for c in chars}),
        "distinct_x": len({roster["characters"][r]["x"] for r in roster["characters"]}),
        "render_scale": (roster["camera"] or {}).get("scale"),
    }


def badge_summary(index):
    """Which badge glyphs the room actually drew, and how often.

    Exists because the first baseline did not have it and could not be read
    without it: every one of its 235 tool-frames was `Bash`, so every badge was
    the terminal glyph, and six characters showing six identical bubbles looks
    like the product failing when it is the workload being uniform.

    Two views, from the two sources, and they answer different questions:

      `badge_agent_frames`: the glyph the scene put over a character, counted
      per (frame, character). This is the picture.
      `tool_agent_frames`: the tool the deltas say that character had open.
      This is reality, and it counts calls no frame ever caught.

    `frames_by_distinct_classes` is the one the design is really asking about: a
    frame holding three different glyphs at once is the case the badge table
    exists for, and no capture before this one contained a single one."""
    badge_frames, tool_frames, distinct = {}, {}, {}
    attention_frames = 0
    for record in index:
        classes = set()
        for character in record["scene_intents"]["characters"].values():
            if character["badge_attention"]:
                attention_frames += 1
            glyph = character["badge"]
            if glyph:
                badge_frames[glyph] = badge_frames.get(glyph, 0) + 1
                classes.add(glyph)
        for agent in record["truth"]["agents"]:
            for tool in agent["open_calls"]:
                tool_frames[tool] = tool_frames.get(tool, 0) + 1
        distinct[len(classes)] = distinct.get(len(classes), 0) + 1
    return {
        "badge_agent_frames": dict(sorted(badge_frames.items(),
                                          key=lambda kv: -kv[1])),
        "tool_agent_frames": dict(sorted(tool_frames.items(),
                                         key=lambda kv: -kv[1])),
        "distinct_classes_max": max(distinct) if distinct else 0,
        "frames_by_distinct_classes": {str(k): distinct[k] for k in sorted(distinct)},
        "frames_with_three_or_more_classes": sum(v for k, v in distinct.items() if k >= 3),
        "attention_agent_frames": attention_frames,
    }


def motion_summary(index):
    """How much the room moves, split by whether anything was working.

    Reported rather than judged. "Whether any are idle" is a question an
    observer answers off motion, so how much motion there is inside an open call
    and how much there is outside one is a number the S5 judgement wants in
    front of it. It is not a pass mark and there is no threshold here."""
    def stats(rows, key):
        values = sorted(v for v in (r["pixels"].get(key) for r in rows) if v is not None)
        if not values:
            return None
        return {"n": len(values), "median": values[len(values) // 2],
                "min": values[0], "max": values[-1],
                "zero": sum(1 for v in values if v == 0)}

    busy = [r for r in index if r["truth"]["working_count"] > 0]
    quiet = [r for r in index if r["truth"]["working_count"] == 0
             and r["truth"]["agent_count"] > 0]
    return {
        "note": "changed_fraction_vs_previous is sampled at the filmstrip interval and "
                "aliases against the ambient loop; motion_fraction is the short probe and "
                "is the one that says whether the room is moving",
        "while_working": {"between_frames": stats(busy, "changed_fraction_vs_previous"),
                          "probe": stats(busy, "motion_fraction")},
        "while_nothing_working": {"between_frames": stats(quiet, "changed_fraction_vs_previous"),
                                  "probe": stats(quiet, "motion_fraction")},
    }


# ----------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--capture", required=True, help="captured hook stream (JSONL)")
    ap.add_argument("--out", required=True, help="run directory to write into")
    ap.add_argument("--interval", type=float, default=1.5, help="seconds between frames")
    ap.add_argument("--size", default="720x400",
                    help="viewport in pixels; 720x400 is PanelSize.room, the real panel")
    ap.add_argument("--theme", default=None, help="force a room; default is the app's own "
                                                  "derivation from the capture's cwd")
    ap.add_argument("--spriteroom", default=os.path.join(REPO, ".build/debug/spriteroom"))
    ap.add_argument("--replay", default=os.path.join(REPO, ".build/debug/spriteroom-replay"))
    ap.add_argument("--no-pixels", action="store_true",
                    help="skip PNG decoding (frame-to-frame change fractions)")
    ap.add_argument("--motion-probe", type=float, default=0.25,
                    help="seconds after each frame to render a second time, to measure "
                         "whether the room is moving there; 0 disables")
    args = ap.parse_args()

    size = tuple(int(x) for x in args.size.split("x"))
    out = os.path.abspath(args.out)
    frames_dir = os.path.join(out, "frames")
    os.makedirs(frames_dir, exist_ok=True)

    lines = [l for l in open(args.capture) if l.strip()]
    payload_sizes = [len(l) for l in lines]
    entries = [json.loads(l) for l in lines]
    if not entries:
        print("capture is empty: %s" % args.capture)
        return 2
    def when(e):
        return datetime.fromisoformat(e["_receivedAt"])
    origin, last = when(entries[0]), when(entries[-1])
    duration = (last - origin).total_seconds()

    marks = []
    t = 0.0
    while t < duration:
        marks.append(round(t, 3))
        t += args.interval
    marks.append(round(duration, 3))
    print("capture: %d events, %.2f s, %d frames every %.2f s at %dx%d"
          % (len(entries), duration, len(marks), args.interval, size[0], size[1]))

    # 1. Reality. One replay of the whole stream; folded forward per mark.
    p = subprocess.run([args.replay, os.path.abspath(args.capture)],
                       capture_output=True, text=True, cwd=REPO, timeout=600)
    open(os.path.join(out, "deltas.log"), "w").write(p.stdout + p.stderr)
    deltas = parse_deltas(p.stdout)
    print("deltas: %d parsed from spriteroom-replay" % len(deltas))

    # 2. The whole intent trace, from one simulation to the end of the capture.
    trace, _, room, unmapped = render(args.spriteroom, os.path.abspath(args.capture),
                            frames_dir, size, [duration], args.theme)
    open(os.path.join(out, "intents.log"), "w").write(trace)
    intents = parse_intents(trace)
    print("room: %s   intent batches: %d" % (room, len(intents)))

    # 3. One render per mark: the frame, and the scene's own roster at it. Split
    #    per mark because `debugRoster` prints at the end of a run, so the only
    #    way to have it *at* a frame is to end the run there. The renderer is
    #    deterministic, so this is the same simulation each time.
    #    **This is the expensive step and its cost scales with the capture, not
    #    just the frame count**, because every invocation re-parses the whole
    #    JSONL. At 132 KB that is 0.5 s a frame; the badge-diverse baseline came
    #    to 57 MB: ten `Edit` calls on a 5.5 MB file, each POSTing the file back
    #    in `tool_response`, and the same 225 frames took ten times as long.
    #    Worth knowing before pointing this at a capture full of large payloads.
    #
    #    A second render `--motion-probe` seconds after each mark answers a
    #    question a filmstrip cannot: *is the room moving here*. Two frames 1.5 s
    #    apart come out pixel-identical about half the time even while five
    #    characters are working, because the ambient loop lands on the same phase
    #: measured, not assumed. So "identical to the previous frame" is not
    #    evidence the room is static, and a short probe is what tells them apart.
    motion_dir = os.path.join(out, "motion")
    if args.motion_probe:
        os.makedirs(motion_dir, exist_ok=True)
    rosters, files, probes = {}, {}, {}
    for i, m in enumerate(marks):
        stdout, written, _, _ = render(args.spriteroom, os.path.abspath(args.capture),
                                    frames_dir, size, [m], args.theme)
        rosters[m] = parse_roster(stdout)
        files[m] = written[-1] if written else None
        if args.motion_probe:
            _, probe_written, _, _ = render(args.spriteroom, os.path.abspath(args.capture),
                                            motion_dir, size, [m + args.motion_probe],
                                            args.theme)
            probes[m] = probe_written[-1] if probe_written else None
        sys.stdout.write("\r  rendered %d/%d" % (i + 1, len(marks)))
        sys.stdout.flush()
    print()

    rosterlog = open(os.path.join(out, "rosters.log"), "w")
    index, all_findings, previous_png, previous_truth = [], [], None, None
    for m in marks:
        drawn_at, roster_at = render_instants(m)
        # The ground truth written beside the frame is the truth at the instant
        # the *frame* was drawn. The roster is compared against its own instant,
        # one tick later, because that is the world it describes.
        truth = truth_at(deltas, drawn_at)
        roster = rosters[m]
        scene = intents_at(intents, drawn_at)
        findings = compare(truth_at(deltas, roster_at), truth, roster, scene)
        obs = observations(truth, roster, scene)

        png = os.path.join(frames_dir, files[m]) if files[m] else None
        pixels = {"file": files[m]}
        if png and os.path.exists(png):
            data = open(png, "rb").read()
            pixels["sha256"] = hashlib.sha256(data).hexdigest()
            pixels["bytes"] = len(data)
            if not args.no_pixels:
                current = decode_rgba(png)
                pixels["changed_fraction_vs_previous"] = changed_fraction(previous_png, current)
                previous_png = current
                if args.motion_probe and probes.get(m):
                    probe_png = os.path.join(motion_dir, probes[m])
                    if os.path.exists(probe_png):
                        pixels["motion_probe_seconds"] = args.motion_probe
                        pixels["motion_fraction"] = changed_fraction(
                            current, decode_rgba(probe_png))

        # A frame that is byte-identical to the one before it while the world
        # changed underneath is the one pixel-level disagreement worth naming:
        # the room did not move when reality did.
        if previous_truth is not None and pixels.get("sha256"):
            same_picture = pixels["sha256"] == previous_truth["sha256"]
            moved = (truth["agent_count"] != previous_truth["agent_count"]
                     or truth["working_count"] != previous_truth["working_count"]
                     or truth["dormant_count"] != previous_truth["dormant_count"])
            if same_picture and moved:
                findings.append({
                    "kind": "static-frame-during-change",
                    "detail": "pixel-identical to the previous frame, but agents/working/"
                              "dormant went %s → %s"
                              % ((previous_truth["agent_count"], previous_truth["working_count"],
                                  previous_truth["dormant_count"]),
                                 (truth["agent_count"], truth["working_count"],
                                  truth["dormant_count"]))})
        previous_truth = {"sha256": pixels.get("sha256"),
                          "agent_count": truth["agent_count"],
                          "working_count": truth["working_count"],
                          "dormant_count": truth["dormant_count"]}

        record = {
            "t": m,
            "drawn_at": round(drawn_at, 5),
            "roster_at": round(roster_at, 5),
            "frame": files[m],
            "room": room,
            "viewport": {"width": size[0], "height": size[1]},
            "truth": truth,
            "scene_roster": roster,
            "scene_intents": scene,
            "observations": obs,
            "badge_classes": sorted({c["badge"] for c in scene["characters"].values()
                                     if c["badge"]}),
            "pixels": pixels,
            "disagreements": findings,
        }
        index.append(record)
        for f in findings:
            all_findings.append(dict(f, t=m, frame=files[m]))

        if files[m]:
            sidecar = os.path.join(frames_dir, files[m][:-4] + ".json")
            json.dump(record, open(sidecar, "w"), indent=2)
        rosterlog.write("t=%.3f  %s\n" % (m, json.dumps(roster)))
    rosterlog.close()

    summary = {
        "capture": os.path.abspath(args.capture),
        "events": len(entries),
        "duration_seconds": duration,
        "origin": entries[0]["_receivedAt"],
        "frames": len(marks),
        "interval_seconds": args.interval,
        "viewport": {"width": size[0], "height": size[1]},
        "room": room,
        "unmapped_tools": unmapped,
        # The hook payload sizes, because one of them is a surprise worth
        # keeping: an `Edit` on a 5.5 MB file POSTs a 5.7 MB `PostToolUse` body,
        # the whole file coming back in `tool_response`. Ten of them made a
        # 57 MB capture out of 212 events. Every one of those bodies is read by
        # a listener that S2 holds to 10 ms at p99, and no fixture contains one.
        "payload_bytes": {
            "total": sum(payload_sizes),
            "max": max(payload_sizes) if payload_sizes else 0,
            "over_1mb": sum(1 for s in payload_sizes if s > 1_000_000),
        },
        "peak_agents": max(r["truth"]["agent_count"] for r in index),
        "agent_types_seen": sorted({t for r in index for t in r["truth"]["agent_types"]}),
        "peak_distinct_variants": max(r["observations"]["distinct_variants"] for r in index),
        "variants_ever_shared": sorted({v for r in index
                                        for v in r["observations"]["shared_variants"]}),
        "render_scales": sorted({r["observations"]["render_scale"] for r in index
                                 if r["observations"]["render_scale"] is not None}),
        "distinct_frames": len({r["pixels"].get("sha256") for r in index}),
        "badges": badge_summary(index),
        "motion": motion_summary(index),
        "disagreement_count": len(all_findings),
        "disagreement_kinds": sorted({f["kind"] for f in all_findings}),
    }
    json.dump({"summary": summary, "frames": index}, open(os.path.join(out, "index.json"), "w"),
              indent=2)
    json.dump(all_findings, open(os.path.join(out, "disagreements.json"), "w"), indent=2)

    print(json.dumps(summary, indent=2))
    if all_findings:
        print("\n%d mechanical disagreement(s):" % len(all_findings))
        kinds = {}
        for f in all_findings:
            kinds.setdefault(f["kind"], []).append(f)
        for kind in sorted(kinds):
            rows = kinds[kind]
            print("  %-28s %4d  first at t=%.2f: %s"
                  % (kind, len(rows), rows[0]["t"], rows[0].get("detail", "")))
    else:
        print("\nno mechanical disagreement between picture and ground truth")
    return 0


if __name__ == "__main__":
    sys.exit(main())
