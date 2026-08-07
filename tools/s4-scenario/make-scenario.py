#!/usr/bin/env python3
"""Build an S4 rendering scenario: six concurrent agents, three of one type.

NOT a fixture. It does not go in fixtures/ and it is not ground truth.

Every line is a *copy of a real captured payload* from
fixtures/three-subagents.jsonl with three fields rewritten — agent_id,
agent_type, tool_use_id — and the timestamps shifted so the clones overlap. No
event name, no field shape and no value structure is invented; the agent_ids
keep the observed `a` + 16 hex form.

It exists because a live six-agent capture needs a permission this environment
refuses (writing a permissions block into a sandbox settings.json, and
--dangerously-skip-permissions, are both blocked), and S4 is a claim about
*pixels at a zoom level*, which a driver can produce honestly as long as it says
what it is. Every line is stamped "_synthetic": true, same convention as the
tail of fixtures/unknown-events.jsonl.
"""
import json, os, sys

SRC = "/Users/henrykanaskie/coding_projects/teamwork/fixtures/three-subagents.jsonl"
OUT = sys.argv[1]

lines = [json.loads(l) for l in open(SRC)]

# The real subagent whose lifecycle we clone: the general-purpose one, because
# it is the longest and it is the case M4 saw fail.
TEMPLATE = "a894ded5b0c4b18de"

# New ids in the observed shape: 'a' + 16 hex. Chosen so the last three
# characters — the discriminator the nameplate shows — are all different, which
# is the thing under test.
CLONES = [
    ("a1c0ffee0badf00d1", "general-purpose", 0.0),
    ("a2d1e5ea1b0bcafe2", "general-purpose", 1.7),
    ("a3f00dfaceb00c123", "general-purpose", 3.4),
    ("a4b0a7ed1ce50da74", "Explore", 5.1),
    ("a5c0de1a5eb1a5e05", "Explore", 6.8),
]

template_lines = [l for l in lines if l["payload"].get("agent_id") == TEMPLATE]
assert template_lines, "template subagent not in the capture"

def shift(ts, seconds):
    from datetime import datetime, timedelta
    d = datetime.fromisoformat(ts)
    return (d + timedelta(seconds=seconds)).isoformat().replace("+00:00", "+00:00")

out = []
# The main thread's own stream, untouched, minus the real subagents — the six
# characters on screen are main plus five clones.
for l in lines:
    if "agent_id" in l["payload"]:
        continue
    out.append(l)

for i, (aid, atype, delay) in enumerate(CLONES):
    for l in template_lines:
        c = json.loads(json.dumps(l))
        p = c["payload"]
        p["agent_id"] = aid
        p["agent_type"] = atype
        for key in ("tool_use_id",):
            if key in p:
                p[key] = "%s_c%d" % (p[key], i)
        for key in ("tool_calls",):
            if key in p and isinstance(p[key], list):
                for call in p[key]:
                    if isinstance(call, dict) and "tool_use_id" in call:
                        call["tool_use_id"] = "%s_c%d" % (call["tool_use_id"], i)
        c["_receivedAt"] = shift(c["_receivedAt"], delay)
        c["_synthetic"] = True
        c["_derived_from"] = "fixtures/three-subagents.jsonl"
        out.append(c)

out.sort(key=lambda l: l["_receivedAt"])
with open(OUT, "w") as f:
    for l in out:
        f.write(json.dumps(l, ensure_ascii=False) + "\n")
print("wrote %s: %d lines, %d synthetic" % (OUT, len(out), sum(1 for l in out if l.get("_synthetic"))))
