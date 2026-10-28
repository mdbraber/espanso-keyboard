#!/usr/bin/env python3
"""A stand-in source for scripts/sourcetest: hints "Careful" at any text with "hate" in it, and logs every update."""
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

port, log = int(sys.argv[1]), open(sys.argv[2], "a", buffering=1)

class Source(BaseHTTPRequestHandler):
    def do_POST(self):
        update = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        log.write(json.dumps(update) + "\n")
        text = update["before"] + update["after"]
        body = json.dumps({"hint": "Careful"} if "hate" in text else {}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

HTTPServer(("127.0.0.1", port), Source).serve_forever()
