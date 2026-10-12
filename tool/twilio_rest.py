#!/usr/bin/env python3
"""Sets up proof-of-concept scenarios through Twilio's REST API.

Uses the same git-ignored tool/twilio-test.env as test_token.py. Test accounts only.

Usage:
    python3 tool/twilio_rest.py removed-conversation <identity>
        Creates a conversation, adds <identity>, then removes it again (criterion C7).
        Prints the conversation SID for --dart-define=C7_SID=…
    python3 tool/twilio_rest.py pair <pair-id>
        Creates <pair-id>-main and <pair-id>-other with <pair-id>-responder and
        <pair-id>-measurer as participants, for integration_test/poc_pair_test.dart.
    python3 tool/twilio_rest.py conversations <identity> <count>
        Creates <count> conversations with <identity> in each (criterion B1).
    python3 tool/twilio_rest.py send <conversation-sid> <body-prefix>
        Sends three messages, <body-prefix>-1 to -3, from "poc-sender" (criteria E1, E2).
"""

import base64
import json
import sys
import urllib.parse
import urllib.request

from test_token import read_env

ENV = read_env()
BASE = f"https://conversations.twilio.com/v1/Services/{ENV['TWILIO_CONVERSATIONS_SERVICE_SID']}"


def call(method, path, fields=None):
    data = urllib.parse.urlencode(fields).encode() if fields else None
    request = urllib.request.Request(BASE + path, data=data, method=method)
    credentials = f"{ENV['TWILIO_API_KEY_SID']}:{ENV['TWILIO_API_KEY_SECRET']}".encode()
    request.add_header("Authorization", "Basic " + base64.b64encode(credentials).decode())
    with urllib.request.urlopen(request) as response:
        body = response.read()
        return json.loads(body) if body else None


def removed_conversation(identity):
    conversation = call("POST", "/Conversations", {"FriendlyName": f"poc-removed-{identity}"})
    participant = call("POST", f"/Conversations/{conversation['sid']}/Participants", {"Identity": identity})
    call("DELETE", f"/Conversations/{conversation['sid']}/Participants/{participant['sid']}")
    print(conversation["sid"])


def pair(pair_id):
    for name in (f"{pair_id}-main", f"{pair_id}-other"):
        conversation = call("POST", "/Conversations", {"UniqueName": name, "FriendlyName": name})
        for identity in (f"{pair_id}-responder", f"{pair_id}-measurer"):
            call("POST", f"/Conversations/{conversation['sid']}/Participants", {"Identity": identity})
        print(name, conversation["sid"])


def conversations(identity, count):
    for i in range(count):
        conversation = call("POST", "/Conversations", {"FriendlyName": f"poc-{identity}-{i}"})
        call("POST", f"/Conversations/{conversation['sid']}/Participants", {"Identity": identity})
    print(f"{identity}: {count} conversations")


def send(conversation_sid, prefix):
    for i in range(1, 4):
        call("POST", f"/Conversations/{conversation_sid}/Messages", {"Author": "poc-sender", "Body": f"{prefix}-{i}"})
    print(f"sent {prefix}-1..3 to {conversation_sid}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "removed-conversation":
        removed_conversation(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "pair":
        pair(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "conversations":
        conversations(sys.argv[2], int(sys.argv[3]))
    elif len(sys.argv) == 4 and sys.argv[1] == "send":
        send(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
