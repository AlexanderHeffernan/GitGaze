#!/usr/bin/env python3
"""Serves ui/ for browser previews with sample data (no Tauri). Never cached, so edits show on reload."""
import functools, http.server, os, sys

class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

port = int(os.environ.get("PORT", sys.argv[1] if len(sys.argv) > 1 else 5175))
root = os.path.join(os.path.dirname(__file__), "..", "ui")
http.server.ThreadingHTTPServer(("127.0.0.1", port), functools.partial(NoCache, directory=root)).serve_forever()
