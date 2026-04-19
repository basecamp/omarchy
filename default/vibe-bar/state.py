"""Session state model for Vibe Bar daemon."""
import time
from dataclasses import dataclass, field
from typing import Optional, Any


@dataclass
class PendingApproval:
    tool: str
    tool_input: dict
    writer: Any = None  # asyncio.StreamWriter — excluded from JSON serialization


@dataclass
class Session:
    id: str
    agent: str
    status: str  # "running" | "waiting" | "idle" | "done"
    cwd: str
    started_at: float
    last_event: float
    last_tool: Optional[str] = None
    pending: Optional[PendingApproval] = None
    tool_history: list = field(default_factory=list)  # last 10: [{tool, ts}]


class SessionState:
    def __init__(self):
        self.sessions: dict[str, Session] = {}

    def add_session(self, session_id: str, agent: str, cwd: str) -> Session:
        now = time.time()
        session = Session(
            id=session_id,
            agent=agent,
            status="running",
            cwd=cwd,
            started_at=now,
            last_event=now,
        )
        self.sessions[session_id] = session
        return session

    def update_tool(self, session_id: str, tool: str) -> None:
        if session_id in self.sessions:
            s = self.sessions[session_id]
            now = time.time()
            s.last_tool = tool
            s.last_event = now
            s.tool_history = (s.tool_history + [{"tool": tool, "ts": now}])[-10:]
            if s.status == "idle":
                s.status = "running"

    def set_pending(self, session_id: str, pending: PendingApproval) -> None:
        if session_id in self.sessions:
            self.sessions[session_id].pending = pending
            self.sessions[session_id].status = "waiting"
            self.sessions[session_id].last_event = time.time()

    def clear_pending(self, session_id: str) -> None:
        if session_id in self.sessions:
            self.sessions[session_id].pending = None
            self.sessions[session_id].status = "running"
            self.sessions[session_id].last_event = time.time()

    def mark_idle(self, session_id: str) -> None:
        """Session alive but not running a tool (between turns)."""
        if session_id in self.sessions:
            s = self.sessions[session_id]
            if s.status != "waiting":  # don't clobber a pending approval
                s.status = "idle"
            s.last_event = time.time()

    def mark_done(self, session_id: str) -> None:
        if session_id in self.sessions:
            self.sessions[session_id].status = "done"
            self.sessions[session_id].last_event = time.time()

    def prune_done(self, max_age_seconds: float = 60.0) -> None:
        now = time.time()
        to_remove = [
            sid for sid, s in self.sessions.items()
            if s.status == "done" and (now - s.last_event) > max_age_seconds
        ]
        for sid in to_remove:
            del self.sessions[sid]

    def summary(self) -> dict:
        sessions = list(self.sessions.values())
        return {
            "total": len(sessions),
            "running": sum(1 for s in sessions if s.status == "running"),
            "waiting": sum(1 for s in sessions if s.status == "waiting"),
            "idle": sum(1 for s in sessions if s.status == "idle"),
        }

    def to_json(self) -> dict:
        sessions_list = []
        for s in self.sessions.values():
            entry = {
                "id": s.id,
                "agent": s.agent,
                "status": s.status,
                "cwd": s.cwd,
                "started_at": s.started_at,
                "last_event": s.last_event,
                "last_tool": s.last_tool,
                "tool_history": s.tool_history,
                "pending": None,
            }
            if s.pending:
                entry["pending"] = {
                    "tool": s.pending.tool,
                    "tool_input": s.pending.tool_input,
                }
            sessions_list.append(entry)
        return {"sessions": sessions_list, "summary": self.summary()}
