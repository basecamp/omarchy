#!/usr/bin/python

import json
import os
import socket
import struct
import subprocess
import sys

NETWORK_CONTRACT = "24d172b971ac832c86d4e28c224bfd7e912aa1ea3de4517aa09af2c02d362a20"
MEDIA_CONTRACT = "f060bfec526a4355bd3431d39310bf96e61907f26be0e0dea6e6e8c2d28a415c"
NETWORK_SCOPE = '{"methods":["GET"],"origins":["https://fixture.invalid"]}'
MEDIA_SCOPE = '{"controls":["pause","stop","mute","volume","status"],"sourceHandles":["network.fetch"]}'


def text(value):
    encoded = value.encode()
    return struct.pack(">H", len(encoded)) + encoded


def frame(correlation, adapter, contract, operation, scope, payload):
    encoded = json.dumps(payload, separators=(",", ":")).encode()
    body = (
        text(adapter)
        + text(contract)
        + struct.pack(">I", 1)
        + text(operation)
        + text(scope)
        + struct.pack(">I", len(encoded))
        + encoded
    )
    return struct.pack(">IBBBBQI", 0x4F505256, 1, 1, 0, 0, correlation, len(body)) + body


def start(path):
    parent, child = socket.socketpair(socket.AF_UNIX, socket.SOCK_SEQPACKET)
    process = subprocess.Popen([path], stdin=child)
    child.close()
    return process, parent


def call(channel, correlation, adapter, contract, operation, scope, payload):
    channel.send(frame(correlation, adapter, contract, operation, scope, payload))
    response = channel.recv(65557)
    magic, version, kind, zero_a, zero_b, observed, length = struct.unpack(
        ">IBBBBQI", response[:20]
    )
    assert (magic, version, kind, zero_a, zero_b, observed) == (
        0x4F505256,
        1,
        2,
        0,
        0,
        correlation,
    )
    assert length == len(response) - 20 and response[20] == 0
    return json.loads(response[21:])


def fetch(channel, correlation, path="/stations", origin="https://fixture.invalid"):
    return call(
        channel,
        correlation,
        "bounded-network-fetch",
        NETWORK_CONTRACT,
        "fetch",
        NETWORK_SCOPE,
        {
            "method": "GET",
            "origin": origin,
            "path": path,
            "responseType": "json",
            "mediaJsonPointers": ["/*/url"],
        },
    )


def main():
    process, channel = start(sys.argv[1])
    result = fetch(channel, 1)
    assert result["ok"] is True and result["status"] == 200
    handle = result["sourceHandles"]["/0/url"]
    cleartext_handle = result["sourceHandles"]["/1/url"]
    assert len(handle) == 32 and len(cleartext_handle) == 32
    assert result["json"][0]["url"] == "https://stream.example/audio"
    assert result["json"][1]["url"] == "http://stream.example:8000/audio"

    denied = fetch(channel, 2, origin="https://example.com")
    assert denied == {"error": "outside-scope", "ok": False}
    redirected = fetch(channel, 3, path="/redirect")
    assert redirected == {"error": "redirect-rejected", "ok": False}
    private = fetch(channel, 4, path="/private-source")
    assert private["ok"] is True and private["sourceHandles"] == {}

    fractional = call(
        channel,
        5,
        "activation-media-stream",
        MEDIA_CONTRACT,
        "play",
        MEDIA_SCOPE,
        {"handle": handle, "volume": 42.5},
    )
    assert fractional == {"error": "invalid-request", "ok": False}

    playing = call(
        channel,
        6,
        "activation-media-stream",
        MEDIA_CONTRACT,
        "play",
        MEDIA_SCOPE,
        {"handle": cleartext_handle, "volume": 42},
    )
    assert playing["ok"] is True and playing["running"] is True and playing["volume"] == 42
    paused = call(
        channel,
        7,
        "activation-media-stream",
        MEDIA_CONTRACT,
        "control",
        MEDIA_SCOPE,
        {"control": "pause"},
    )
    assert paused["ok"] is True and paused["paused"] is True
    stopped = call(
        channel,
        8,
        "activation-media-stream",
        MEDIA_CONTRACT,
        "control",
        MEDIA_SCOPE,
        {"control": "stop"},
    )
    assert stopped["ok"] is True and stopped["running"] is False
    channel.close()
    assert process.wait(timeout=2) == 0

    other, other_channel = start(sys.argv[1])
    stale = call(
        other_channel,
        9,
        "activation-media-stream",
        MEDIA_CONTRACT,
        "play",
        MEDIA_SCOPE,
        {"handle": handle},
    )
    assert stale == {"error": "invalid-handle", "ok": False}
    other_channel.close()
    assert other.wait(timeout=2) == 0


if __name__ == "__main__":
    main()
