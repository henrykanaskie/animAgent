#!/usr/bin/env python3
"""A one-tool MCP server, so the room can be caught drawing the `plug` badge.

Registered into the observe sandbox's `.mcp.json`, never anywhere else. Claude
Code names an MCP tool `mcp__<server>__<tool>` in the hook payload, and
`ToolBadge.badge(forTool:)` routes anything with that prefix to `.plug`. No
capture in `fixtures/` has ever contained one, so the badge has never been seen
in a real room.

**Why it exists at all, and why it is a `hold`.** Every tool in Claude Code
except `Bash` closes in about ten milliseconds, while the model takes seconds to
decide on the next one. So a character driven by `Read` or `Edit` is idle
essentially all of the time and the odds of a filmstrip frame catching its badge
are near zero: the first baseline caught 235 tool-frames and every one was
`Bash`, because `Bash` was the only tool that could be made to last. A tool that
holds for a stated number of seconds is what makes the badge *observable*, and
observability is the whole point of the capture.

The call is real: a real MCP server, a real stdio transport, a real tool call,
real hook payloads. What is arranged is how long it takes, and that is stated
here rather than hidden.

Speaks the subset of MCP that Claude Code needs to start a stdio server and call
a tool: `initialize`, `tools/list`, `tools/call`, and it answers `ping`.
Line-delimited JSON-RPC 2.0 on stdin/stdout. Python 3 stdlib only.
"""

import json
import sys
import time

PROTOCOL = "2024-11-05"

TOOLS = [
    {
        "name": "hold",
        "description": (
            "Hold this tool call open for a number of seconds, then return. "
            "Used to keep a character visibly working for a known duration."),
        "inputSchema": {
            "type": "object",
            "properties": {
                "seconds": {"type": "number",
                            "description": "how long to hold, 0-300"},
                "label": {"type": "string",
                          "description": "free text echoed back"},
            },
            "required": ["seconds"],
        },
    },
]


def send(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()


def result(request_id, payload):
    send({"jsonrpc": "2.0", "id": request_id, "result": payload})


def error(request_id, code, message):
    send({"jsonrpc": "2.0", "id": request_id,
          "error": {"code": code, "message": message}})


def call_tool(params):
    name = params.get("name")
    args = params.get("arguments") or {}
    if name != "hold":
        return None
    seconds = args.get("seconds", 0)
    try:
        seconds = max(0.0, min(300.0, float(seconds)))
    except (TypeError, ValueError):
        seconds = 0.0
    time.sleep(seconds)
    label = args.get("label", "")
    return {"content": [{"type": "text",
                         "text": "held %.1fs %s" % (seconds, label)}]}


def main():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except ValueError:
            continue
        method = message.get("method")
        request_id = message.get("id")
        # Notifications carry no id and are never answered.
        if request_id is None:
            continue
        if method == "initialize":
            result(request_id, {
                "protocolVersion": PROTOCOL,
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "observe", "version": "1.0.0"},
            })
        elif method == "ping":
            result(request_id, {})
        elif method == "tools/list":
            result(request_id, {"tools": TOOLS})
        elif method == "tools/call":
            payload = call_tool(message.get("params") or {})
            if payload is None:
                error(request_id, -32602, "no such tool")
            else:
                result(request_id, payload)
        else:
            error(request_id, -32601, "method not found: %s" % method)


if __name__ == "__main__":
    main()
