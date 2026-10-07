#!/usr/bin/env python3
"""Prints a Twilio Conversations access token for the plugin's device tests.

Real apps get tokens from their own backend. This script exists so the native
code can be tested against a personal Twilio account without one.

Credentials are read from tool/twilio-test.env (git-ignored):

    TWILIO_ACCOUNT_SID=AC...
    TWILIO_API_KEY_SID=SK...
    TWILIO_API_KEY_SECRET=...
    TWILIO_CONVERSATIONS_SERVICE_SID=IS...

Usage:
    python3 tool/test_token.py <identity> [ttl-seconds, default 3600]

Standard library only, so it runs on any machine with Python 3.
"""

import base64
import hashlib
import hmac
import json
import pathlib
import sys
import time

ENV_FILE = pathlib.Path(__file__).with_name("twilio-test.env")
REQUIRED = (
    "TWILIO_ACCOUNT_SID",
    "TWILIO_API_KEY_SID",
    "TWILIO_API_KEY_SECRET",
    "TWILIO_CONVERSATIONS_SERVICE_SID",
)


def read_env():
    if not ENV_FILE.exists():
        sys.exit(f"missing {ENV_FILE}; see the comment at the top of this script")
    values = {}
    for line in ENV_FILE.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    missing = [key for key in REQUIRED if not values.get(key)]
    if missing:
        sys.exit(f"{ENV_FILE} is missing: {', '.join(missing)}")
    return values


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def access_token(env, identity, ttl):
    """A Twilio access token is a JWT signed with the API key secret, carrying a chat grant."""
    now = int(time.time())
    header = {"typ": "JWT", "alg": "HS256", "cty": "twilio-fpa;v=1"}
    payload = {
        "jti": f"{env['TWILIO_API_KEY_SID']}-{now}",
        "iss": env["TWILIO_API_KEY_SID"],
        "sub": env["TWILIO_ACCOUNT_SID"],
        "iat": now,
        "exp": now + ttl,
        "grants": {
            "identity": identity,
            "chat": {"service_sid": env["TWILIO_CONVERSATIONS_SERVICE_SID"]},
        },
    }
    signing_input = ".".join(
        b64url(json.dumps(part, separators=(",", ":")).encode()) for part in (header, payload)
    )
    signature = hmac.new(
        env["TWILIO_API_KEY_SECRET"].encode(), signing_input.encode(), hashlib.sha256
    ).digest()
    return f"{signing_input}.{b64url(signature)}"


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    print(access_token(read_env(), sys.argv[1], int(sys.argv[2]) if len(sys.argv) == 3 else 3600))
