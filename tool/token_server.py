#!/usr/bin/env python3
"""A development token server for the example app.

Real apps get tokens from their own backend. This stands in for that backend on a
developer's machine, using the same git-ignored tool/twilio-test.env as
test_token.py. Use it only with a test Twilio account: anyone who can reach it
can get a token for any identity.

Usage:
    python3 tool/token_server.py [port, default 8787]

Then, from a phone:
    GET http://<this machine's address>:8787/token?identity=alice&ttl=180

Android over USB can use localhost after `adb reverse tcp:8787 tcp:8787`.
iOS needs the machine's Wi-Fi address, which is printed at start.
"""

import http.server
import socket
import sys
import urllib.parse

from test_token import access_token, read_env

ENV = read_env()


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        query = urllib.parse.parse_qs(url.query)
        identity = query.get("identity", [""])[0].strip()
        if url.path != "/token" or not identity:
            self.reply(400, "usage: /token?identity=<identity>[&ttl=<seconds>]")
            return
        try:
            ttl = int(query.get("ttl", ["3600"])[0])
        except ValueError:
            self.reply(400, "ttl must be a number of seconds")
            return
        self.reply(200, access_token(ENV, identity, ttl))

    def reply(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt, *args):
        # The request line holds no secret, but keep tokens out of the log by not echoing replies.
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def lan_address():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        try:
            s.connect(("10.255.255.255", 1))
            return s.getsockname()[0]
        except OSError:
            return "127.0.0.1"


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    print(f"token server on http://{lan_address()}:{port}/token?identity=<identity>&ttl=<seconds>")
    http.server.ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
