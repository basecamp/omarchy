#!/usr/bin/env python3
"""Stream Claude Code project JSONL files and emit compact usage stats.

This replaces the QML-side `rg --json ... | StdioCollector` path, which can
materialize 100MB+ of ripgrep JSON in the Quickshell process. The helper keeps
that work in a short-lived Python process, parses line-by-line, and returns a
single compact JSON object that matches the fields Claude.qml expects.
"""

from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import hashlib
import json
import os
import sys
import time
from pathlib import Path
from typing import Any


def expand_path(value: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(value))).resolve()


def date_string(value: dt.date) -> str:
    return value.strftime("%Y-%m-%d")


def recent_date_strings() -> list[str]:
    today = dt.datetime.now().date()
    return [date_string(today - dt.timedelta(days=offset)) for offset in range(6, -1, -1)]


def local_date_string() -> str:
    return date_string(dt.datetime.now().date())


def local_date_from_timestamp(value: Any) -> str:
    if value is None:
        return local_date_string()

    if isinstance(value, (int, float)):
        try:
            seconds = float(value) / 1000.0 if float(value) > 10_000_000_000 else float(value)
            return date_string(dt.datetime.fromtimestamp(seconds).date())
        except Exception:
            return local_date_string()

    raw = str(value).strip()
    if not raw:
        return local_date_string()

    # Claude JSONL timestamps are usually ISO-8601. Python accepts offsets but
    # not a trailing Z until we normalize it to +00:00.
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone()
        return date_string(parsed.date())
    except Exception:
        return local_date_string()


def usage_token(usage: dict[str, Any], snake_key: str, camel_key: str) -> int:
    value = usage.get(snake_key, usage.get(camel_key, 0))
    try:
        return round(float(value or 0))
    except Exception:
        return 0


def empty_bucket() -> dict[str, int]:
    return {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
    }


def iter_jsonl_files(projects_path: Path):
    if not projects_path.is_dir():
        return
    yield from projects_path.rglob("*.jsonl")


def scan(projects_path: Path) -> dict[str, Any]:
    today = local_date_string()
    recent_dates = recent_date_strings()
    recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}

    seen: set[str] = set()
    sessions: set[str] = set()
    today_sessions: set[str] = set()
    today_tokens: dict[str, int] = {}
    usage_by_model: dict[str, dict[str, int]] = {}
    prompts = 0
    today_prompt_count = 0
    today_token_total = 0
    malformed_lines = 0
    scanned_files = 0

    for path in iter_jsonl_files(projects_path) or []:
        scanned_files += 1
        try:
            with path.open("r", encoding="utf-8", errors="replace") as handle:
                for line_number, line in enumerate(handle, 1):
                    # Cheap pre-filter before JSON parsing. Matches the old rg
                    # search and keeps files with unrelated lines inexpensive.
                    if '"usage":' not in line:
                        continue

                    try:
                        entry = json.loads(line)
                    except Exception:
                        malformed_lines += 1
                        continue

                    message = entry.get("message") if isinstance(entry.get("message"), dict) else {}
                    if entry.get("type") != "assistant" and message.get("role") != "assistant":
                        continue

                    usage = message.get("usage") or entry.get("usage")
                    if not isinstance(usage, dict):
                        continue

                    message_id = message.get("id") or entry.get("messageId") or ""
                    unique_key = str(message_id) if message_id else f"{path}:{entry.get('uuid') or entry.get('requestId') or line_number}"
                    if unique_key in seen:
                        continue
                    seen.add(unique_key)

                    input_tokens = usage_token(usage, "input_tokens", "inputTokens")
                    output_tokens = usage_token(usage, "output_tokens", "outputTokens")
                    cache_read = usage_token(usage, "cache_read_input_tokens", "cacheReadInputTokens")
                    cache_write = usage_token(usage, "cache_creation_input_tokens", "cacheCreationInputTokens")
                    total = input_tokens + output_tokens + cache_read + cache_write
                    if total <= 0:
                        continue

                    model = str(message.get("model") or entry.get("model") or "claude")
                    day = local_date_from_timestamp(entry.get("timestamp") or message.get("timestamp"))
                    session_key = str(entry.get("sessionId") or path)
                    sessions.add(session_key)
                    prompts += 1

                    bucket = usage_by_model.setdefault(model, empty_bucket())
                    bucket["inputTokens"] += input_tokens
                    bucket["outputTokens"] += output_tokens
                    bucket["cacheReadInputTokens"] += cache_read
                    bucket["cacheCreationInputTokens"] += cache_write

                    if day in recent:
                        # Preserve existing QML behavior: recentDays.messageCount
                        # is actually a token total, despite the legacy name.
                        recent[day]["messageCount"] += total

                    if day == today:
                        today_prompt_count += 1
                        today_sessions.add(session_key)
                        today_token_total += total
                        today_tokens[model] = today_tokens.get(model, 0) + total
        except Exception as exc:
            print(f"Ignoring unreadable Claude project file {path}: {exc}", file=sys.stderr)

    recent_days = [recent[day] for day in recent_dates]
    return {
        "schemaVersion": 1,
        "todayPrompts": today_prompt_count,
        "todaySessions": len(today_sessions),
        "todayTotalTokens": today_token_total,
        "todayTokensByModel": today_tokens,
        "recentDays": recent_days,
        "modelUsage": usage_by_model,
        "totalPrompts": prompts,
        "totalSessions": len(sessions),
        "dailyActivity": recent_days,
        "scannedFiles": scanned_files,
        "malformedLines": malformed_lines,
    }


def cache_paths(projects_path: Path) -> tuple[Path, Path]:
    cache_root = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "omarchy" / "model-usage"
    cache_root.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha1(str(projects_path).encode("utf-8")).hexdigest()[:16]
    return cache_root / f"claude-projects-{digest}.json", cache_root / f"claude-projects-{digest}.lock"


def read_fresh_cache(path: Path, max_age_seconds: int) -> str | None:
    if max_age_seconds <= 0 or not path.exists():
        return None
    try:
        if time.time() - path.stat().st_mtime <= max_age_seconds:
            return path.read_text(encoding="utf-8")
    except Exception:
        return None
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("projects_path", nargs="?", default="~/.claude/projects")
    parser.add_argument("--cache-seconds", type=int, default=20)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    projects_path = expand_path(args.projects_path)
    cache_file, lock_file = cache_paths(projects_path)

    if not args.force:
        cached = read_fresh_cache(cache_file, args.cache_seconds)
        if cached is not None:
            print(cached, end="" if cached.endswith("\n") else "\n")
            return 0

    with lock_file.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        if not args.force:
            cached = read_fresh_cache(cache_file, args.cache_seconds)
            if cached is not None:
                print(cached, end="" if cached.endswith("\n") else "\n")
                return 0

        summary = scan(projects_path)
        output = json.dumps(summary, separators=(",", ":"), sort_keys=True) + "\n"
        tmp = cache_file.with_suffix(".json.tmp")
        tmp.write_text(output, encoding="utf-8")
        tmp.replace(cache_file)
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
