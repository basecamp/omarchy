#!/usr/bin/env python3
"""Vibe Bar daemon — receives hook events via Unix socket, maintains session state."""
import argparse
import asyncio
import json
import logging
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(__file__))
from state import SessionState, PendingApproval

DEFAULT_SOCKET = "/tmp/vibe-agents.sock"
DEFAULT_STATE  = "/tmp/vibe-agents.state.json"
DEFAULT_LOG    = "/tmp/vibe-agents.log"
WAYBAR_SIGNAL  = 11  # pkill -RTMIN+11 waybar

log = logging.getLogger("vibe-agents")


class VibeAgentsDaemon:
    def __init__(self, socket_path: str, state_path: str):
        self.socket_path       = socket_path
        self.state_path        = state_path
        self.state             = SessionState()
        self.session_allowlist: dict[str, set[str]] = {}

    def _signal_waybar(self) -> None:
        subprocess.run(
            ["pkill", f"-RTMIN+{WAYBAR_SIGNAL}", "waybar"],
            check=False, capture_output=True,
        )

    def _write_state(self) -> None:
        tmp = self.state_path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(self.state.to_json(), f, indent=2)
        os.replace(tmp, self.state_path)
        self._signal_waybar()

    async def _handle_hook_event(
        self, event: dict, writer: asyncio.StreamWriter
    ) -> None:
        hook_name  = event.get("hook_event_name", "")
        session_id = event.get("session_id", "unknown")
        cwd        = event.get("cwd", "")
        agent      = event.get("agent", "claude-code")

        if hook_name == "SessionStart":
            if session_id not in self.state.sessions:
                self.state.add_session(session_id, agent=agent, cwd=cwd)
            log.info("Session %s started", session_id)

        elif hook_name == "UserPromptSubmit":
            if session_id not in self.state.sessions:
                self.state.add_session(session_id, agent=agent, cwd=cwd)
            log.info("Session %s prompt submitted", session_id)

        elif hook_name == "PreToolUse":
            if session_id not in self.state.sessions:
                self.state.add_session(session_id, agent=agent, cwd=cwd)
            tool = event.get("tool_name", "unknown")
            self.state.update_tool(session_id, tool)
            log.info("Session %s PreToolUse: %s", session_id, tool)
            # Fall through to _write_state() + writer.close()

        elif hook_name == "PermissionRequest":
            if session_id not in self.state.sessions:
                self.state.add_session(session_id, agent=agent, cwd=cwd)
            tool       = event.get("tool_name", "unknown")
            tool_input = event.get("tool_input", {})

            if tool in self.session_allowlist.get(session_id, set()):
                log.info("Session %s auto-approve %s (allowlisted)", session_id, tool)
                self.state.update_tool(session_id, tool)
                response = json.dumps({"decision": "allow"}) + "\n"
                try:
                    writer.write(response.encode())
                    await writer.drain()
                    writer.close()
                except Exception as exc:
                    log.warning("Failed to auto-approve: %s", exc)
                self._write_state()
                return

            pending    = PendingApproval(tool=tool, tool_input=tool_input, writer=writer)
            self.state.set_pending(session_id, pending)
            self._write_state()
            log.info("Session %s PermissionRequest pending: %s", session_id, tool)

            # When Claude Code resolves via the terminal prompt, it kills the hook
            # process. Detect that close by polling the transport — reader.read()
            # was unreliable here (returned EOF instantly after the initial readline).
            async def _on_hook_exit(sid: str = session_id, w: object = writer) -> None:
                import socket as _socket
                transport = w.transport
                while True:
                    await asyncio.sleep(0.25)
                    if transport is None or transport.is_closing():
                        break
                    # Peer-close detection: dup the transport fd and peek via the
                    # raw-socket API (TransportSocket hides recv). A 0-byte peek
                    # means the peer sent FIN — i.e. the hook process exited.
                    ts = transport.get_extra_info("socket")
                    if ts is None or ts.fileno() < 0:
                        break
                    try:
                        probe = _socket.fromfd(ts.fileno(), _socket.AF_UNIX, _socket.SOCK_STREAM)
                    except OSError:
                        break
                    try:
                        probe.setblocking(False)
                        peek = probe.recv(1, _socket.MSG_PEEK)
                        if peek == b"":
                            break  # peer closed
                    except BlockingIOError:
                        pass  # no data yet, peer still alive
                    except OSError:
                        break
                    finally:
                        probe.close()
                s = self.state.sessions.get(sid)
                if s and s.pending and s.pending.writer is w:
                    self.state.clear_pending(sid)
                    self._write_state()
                    log.info("Session %s PermissionRequest hook exited — cleared pending", sid)

            asyncio.create_task(_on_hook_exit())
            return  # keep writer open — _handle_approve or _on_hook_exit will close it

        elif hook_name == "PostToolUse":
            if session_id in self.state.sessions:
                self.state.update_tool(session_id, event.get("tool_name", "unknown"))
                # PostToolUse means the tool ran → any pending approval was resolved
                # (by terminal 'y', Walker allow, or auto-allow). Clear + close writer
                # so the waiting PermissionRequest hook exits cleanly.
                s = self.state.sessions[session_id]
                if s.pending:
                    cleared_tool = s.pending.tool
                    if s.pending.writer is not None:
                        try:
                            s.pending.writer.close()
                        except Exception:
                            pass
                    self.state.clear_pending(session_id)
                    log.info("Session %s PostToolUse cleared pending (%s)", session_id, cleared_tool)

        elif hook_name == "Stop":
            # End of Claude's turn — session is alive but not running a tool.
            # Flip to "idle" (hollow-circle in Waybar) rather than pruning, so
            # the user can see the session is still open and waiting for input.
            if session_id in self.state.sessions:
                s = self.state.sessions[session_id]
                if s.pending:
                    log.info("Session %s Stop received while approval pending — deferring", session_id)
                    self._write_state()
                    writer.close()
                    return
            self.state.mark_idle(session_id)
            log.info("Session %s idle", session_id)

        elif hook_name == "SessionEnd":
            # Session actually closing (user exited Claude) — remove immediately.
            if session_id in self.state.sessions:
                self.state.mark_done(session_id)
                self.state.prune_done(max_age_seconds=0)
                log.info("Session %s ended", session_id)
            self.session_allowlist.pop(session_id, None)

        self._write_state()
        writer.close()

    async def _handle_approve(
        self, event: dict, writer: asyncio.StreamWriter
    ) -> None:
        session_id = event.get("session_id", "")
        decision   = event.get("decision", "allow")

        if session_id in self.state.sessions:
            s = self.state.sessions[session_id]
            if s.pending and s.pending.writer:
                hook_decision = "deny" if decision == "deny" else "allow"
                response = json.dumps({"decision": hook_decision}) + "\n"
                try:
                    s.pending.writer.write(response.encode())
                    await s.pending.writer.drain()
                    s.pending.writer.close()
                except Exception as exc:
                    log.warning("Failed to send approval response: %s", exc)
                if decision == "allow_session":
                    tool = s.pending.tool
                    self.session_allowlist.setdefault(session_id, set()).add(tool)
                    log.info("Session %s allow_session: added %s to allowlist", session_id, tool)
            self.state.clear_pending(session_id)
            self._write_state()
        writer.close()

    async def handle_connection(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        try:
            data = await asyncio.wait_for(reader.readline(), timeout=10.0)
            if not data:
                writer.close()
                return
            event    = json.loads(data.decode().strip())
            msg_type = event.get("type", "hook")

            if msg_type == "hook":
                await self._handle_hook_event(event, writer)
            elif msg_type == "approve":
                await self._handle_approve(event, writer)
            else:
                log.warning("Unknown message type: %s", msg_type)
                writer.close()
        except asyncio.TimeoutError:
            log.warning("Connection timed out")
            writer.close()
        except json.JSONDecodeError as exc:
            log.warning("Invalid JSON: %s", exc)
            writer.close()
        except Exception as exc:
            log.exception("Error handling connection: %s", exc)
            writer.close()

    async def _cleanup_loop(self) -> None:
        """Periodically prune stale done-sessions and sessions with no recent activity."""
        while True:
            await asyncio.sleep(30)
            self.state.prune_done(max_age_seconds=60.0)
            self._write_state()

    async def _animation_ticker(self) -> None:
        """Pulse RTMIN+11 every 250ms when sessions are active, driving smooth animation."""
        while True:
            await asyncio.sleep(0.08)
            active = any(
                s.status in ("running", "waiting")
                for s in self.state.sessions.values()
            )
            if active:
                await asyncio.create_subprocess_exec(
                    "pkill", f"-RTMIN+{WAYBAR_SIGNAL}", "waybar",
                    stdout=asyncio.subprocess.DEVNULL,
                    stderr=asyncio.subprocess.DEVNULL,
                )

    async def run(self) -> None:
        if os.path.exists(self.socket_path):
            os.remove(self.socket_path)
        server = await asyncio.start_unix_server(
            self.handle_connection, path=self.socket_path
        )
        log.info("Daemon listening on %s", self.socket_path)
        self._write_state()
        async with server:
            asyncio.create_task(self._cleanup_loop())
            asyncio.create_task(self._animation_ticker())
            await server.serve_forever()


def _truncate(s: str, n: int) -> str:
    return s if len(s) <= n else s[: n - 1] + "…"


def main() -> None:
    parser = argparse.ArgumentParser(description="Vibe Bar daemon")
    parser.add_argument("--socket", default=DEFAULT_SOCKET)
    parser.add_argument("--state",  default=DEFAULT_STATE)
    parser.add_argument("--log",    default=DEFAULT_LOG)
    args = parser.parse_args()

    logging.basicConfig(
        filename=args.log,
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    daemon = VibeAgentsDaemon(socket_path=args.socket, state_path=args.state)
    try:
        asyncio.run(daemon.run())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
