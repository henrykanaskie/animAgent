#!/usr/bin/env python3
"""Throwaway hook payload logger for M0 ground truth capture.

Listens on 127.0.0.1, accepts POSTs of Claude Code hook payloads, appends each
request body to a JSONL file, and always answers 202 with an empty body.

Not production code. Not in Sources/. Delete after M0 if you like.

    python3 logger.py --port 8787 --out ../../fixtures
    curl -s "http://127.0.0.1:8787/control/scenario?name=parallel-tools"

Each line written is:

    {"_receivedAt": "2026-08-07T01:23:45.678901+00:00", "payload": {...}}

`payload` is the parsed request body, unmodified. If the body is not valid JSON
it is stored as {"_raw": "<text>"} so nothing is lost.
"""

import argparse
import json
import os
import re
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

SAFE_NAME = re.compile(r"^[A-Za-z0-9._-]+$")

_lock = threading.Lock()
_state = {"scenario": "unlabelled", "out_dir": "."}


def _path_for(scenario):
    return os.path.join(_state["out_dir"], scenario + ".jsonl")


def _append(record):
    line = json.dumps(record, ensure_ascii=False, sort_keys=False)
    with _lock:
        with open(_path_for(_state["scenario"]), "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
            fh.flush()
            os.fsync(fh.fileno())


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # silence per-request stderr noise
        pass

    def _accepted(self):
        self.send_response(202)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        url = urlparse(self.path)
        if url.path == "/control/scenario":
            q = parse_qs(url.query)
            name = (q.get("name") or ["unlabelled"])[0]
            if not SAFE_NAME.match(name):
                self.send_response(400)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            with _lock:
                _state["scenario"] = name
            body = json.dumps({"scenario": name, "file": _path_for(name)}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            print("scenario -> %s" % name, flush=True)
            return
        self._accepted()

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""
        received_at = datetime.now(timezone.utc).isoformat(timespec="milliseconds")
        try:
            payload = json.loads(raw.decode("utf-8"))
        except Exception:
            payload = {"_raw": raw.decode("utf-8", "replace")}
        _append({"_receivedAt": received_at, "payload": payload})
        name = payload.get("hook_event_name") if isinstance(payload, dict) else "?"
        print("%s  %s  %s" % (received_at, _state["scenario"], name), flush=True)
        self._accepted()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--out", default=".", help="directory for <scenario>.jsonl files")
    ap.add_argument("--scenario", default="unlabelled")
    args = ap.parse_args()

    _state["out_dir"] = os.path.abspath(args.out)
    _state["scenario"] = args.scenario
    os.makedirs(_state["out_dir"], exist_ok=True)

    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.daemon_threads = True
    print("listening on http://127.0.0.1:%d  out=%s" % (args.port, _state["out_dir"]), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
