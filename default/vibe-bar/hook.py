#!/usr/bin/env python3
"""Vibe Bar hook CLI — called by Claude Code hooks.

PreToolUse:        fire-and-forget (session tracking only, no stdout).
PermissionRequest: block on daemon socket (24h timeout); Walker or native
                   terminal — first responder wins.
Other events:      fire-and-forget.
Fail-open:         daemon unreachable or crash → exit silently, no stdout →
                   Claude Code falls back to its native permission behavior.
"""
import json
import os
import socket
import sys

SOCKET_PATH = os.environ.get("VIBE_AGENTS_SOCKET", "/tmp/vibe-agents.sock")
PERMISSION_REQUEST_TIMEOUT = 24 * 60 * 60  # 24h — mirrors Open Vibe Island


# ── Daemon socket helpers ──────────────────────────────────────────────────────

def _connect_to_daemon(event: dict) -> socket.socket | None:
    """Connect to daemon, send event. Returns open socket or None on failure."""
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(SOCKET_PATH)
        sock.sendall((json.dumps(event) + "\n").encode())
        return sock
    except OSError:
        return None
    except Exception:
        return None


def _read_daemon_decision(sock: socket.socket) -> str | None:
    """Read one decision line. Returns 'allow'/'deny', or None on error/close."""
    try:
        data = b""
        while True:
            chunk = sock.recv(4096)
            if not chunk:
                return None
            data += chunk
            if b"\n" in data:
                break
        return json.loads(data.strip()).get("decision", "allow")
    except Exception:
        return None


def _fire_and_forget(event: dict) -> None:
    """Send event to daemon without waiting for a response."""
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(SOCKET_PATH)
            sock.sendall((json.dumps(event) + "\n").encode())
    except Exception:
        pass


# ── Event handlers ─────────────────────────────────────────────────────────────

def _handle_permission_request(event: dict) -> None:
    """Block on daemon (24h) for Walker decision. Racing with Claude Code's
    native terminal prompt: first responder wins. When Claude Code resolves
    via terminal, it kills this hook process → kernel closes the socket →
    daemon detects EOF and cleans up.

    Fail-open: no output if daemon is unreachable → Claude Code uses native prompt."""
    sock = _connect_to_daemon(event)
    if sock is None:
        return  # daemon down — fall back to Claude's native terminal prompt
    sock.settimeout(PERMISSION_REQUEST_TIMEOUT)
    with sock:
        decision = _read_daemon_decision(sock)
    if decision is None:
        return  # daemon crashed, closed socket, or timed out — fail open

    hook_name = event.get("hook_event_name", "PermissionRequest")
    behavior = "allow" if decision == "allow" else "deny"
    entry: dict = {"behavior": behavior}
    if behavior == "deny":
        entry["message"] = "Denied via Vibe Bar"
    print(json.dumps({
        "continue": True,
        "suppressOutput": True,
        "hookSpecificOutput": {
            "hookEventName": hook_name,
            "decision": entry,
        },
    }))


# ── Entry point ────────────────────────────────────────────────────────────────

def main() -> None:
    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)
    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        sys.exit(0)

    event["type"]  = "hook"
    event["agent"] = "claude-code"

    hook_name = event.get("hook_event_name", "")

    if hook_name == "PermissionRequest":
        _handle_permission_request(event)
    else:
        # PreToolUse, SessionStart/End, UserPromptSubmit, PostToolUse, Stop,
        # Notification, SubagentStart/Stop, PreCompact — all fire-and-forget.
        _fire_and_forget(event)

    sys.exit(0)


if __name__ == "__main__":
    main()
