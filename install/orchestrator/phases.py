"""Phase state machine. Each phase is a (name, callable) pair; callables take
the InstallContext and either return cleanly or raise to abort the install."""

from __future__ import annotations

import json
import time
import traceback
from collections.abc import Callable
from pathlib import Path

from .context import InstallContext
from .ui import error, info


PhaseFn = Callable[[InstallContext], None]


class PhaseError(Exception):
    """Raised when a phase fails. Wrapped with the phase name."""


def run(ctx: InstallContext, phases: list[tuple[str, PhaseFn]]) -> None:
    ctx.state_dir.mkdir(parents=True, exist_ok=True)
    state_path = ctx.state_dir / "state.json"
    state = {"started_at": time.time(), "phases": []}
    _write_state(state_path, state)

    for name, fn in phases:
        info(f"› {name}")
        started = time.time()
        try:
            fn(ctx)
        except Exception as exc:  # noqa: BLE001
            elapsed = time.time() - started
            state["phases"].append({
                "name": name,
                "status": "failed",
                "elapsed": elapsed,
                "error": str(exc),
            })
            _write_state(state_path, state)

            error(f"Phase '{name}' failed after {elapsed:.1f}s: {exc}")
            traceback.print_exc()
            raise PhaseError(f"phase {name} failed: {exc}") from exc

        elapsed = time.time() - started
        state["phases"].append({"name": name, "status": "ok", "elapsed": elapsed})
        _write_state(state_path, state)

    state["finished_at"] = time.time()
    _write_state(state_path, state)


def _write_state(path: Path, state: dict) -> None:
    path.write_text(json.dumps(state, indent=2, default=str))
