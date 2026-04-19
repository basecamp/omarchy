#!/usr/bin/env python3
"""Send approve/deny decision to the Vibe Bar daemon.

Usage: approve.py <session_id> <allow|deny>
"""
import json
import socket
import sys

SOCKET_PATH = "/tmp/vibe-agents.sock"


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <session_id> <allow|deny>", file=sys.stderr)
        sys.exit(1)

    session_id = sys.argv[1]
    decision = sys.argv[2]
    if decision not in ("allow", "deny", "allow_session"):
        print("Decision must be 'allow', 'deny', or 'allow_session'", file=sys.stderr)
        sys.exit(1)

    msg = json.dumps({
        "type": "approve",
        "session_id": session_id,
        "decision": decision,
    }) + "\n"

    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(5.0)
            sock.connect(SOCKET_PATH)
            sock.sendall(msg.encode())
    except OSError:
        print("Daemon not running", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
