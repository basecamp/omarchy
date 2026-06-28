#!/usr/bin/env python3
"""Query opencode's sqlite database and emit compact usage stats."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sqlite3
import sys
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


def number(value: Any) -> int:
    try:
        return int(value or 0)
    except Exception:
        return 0


def scan(db_path: Path) -> dict[str, Any]:
    today = local_date_string()
    recent_dates = recent_date_strings()
    recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}

    today_prompts = 0
    today_sessions: set[str] = set()
    today_total_tokens = 0
    today_tokens_by_model: dict[str, int] = {}

    total_prompts = 0
    total_sessions: set[str] = set()
    model_usage: dict[str, dict[str, int]] = {}

    if not db_path.exists():
        return empty_result()

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro&immutable=1", uri=True, timeout=5)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        cursor.execute("""
            SELECT
                model,
                tokens_input,
                tokens_output,
                tokens_reasoning,
                tokens_cache_read,
                tokens_cache_write,
                cost,
                time_created,
                id,
                title
            FROM session
            WHERE time_created > 0
            ORDER BY time_created DESC
        """)

        for row in cursor:
            raw_model = row["model"]
            if raw_model and isinstance(raw_model, str) and raw_model.strip().startswith("{"):
                try:
                    parsed = json.loads(raw_model)
                    model_id = str(parsed.get("id", raw_model))
                    provider = str(parsed.get("providerID", ""))
                    model = f"{model_id} ({provider})" if provider else model_id
                except Exception:
                    model = str(raw_model)
            else:
                model = str(raw_model or "unknown")
            input_t = number(row["tokens_input"])
            output_t = number(row["tokens_output"])
            reasoning_t = number(row["tokens_reasoning"])
            cache_read = number(row["tokens_cache_read"])
            cache_write = number(row["tokens_cache_write"])
            total = input_t + output_t + reasoning_t + cache_read + cache_write

            if total <= 0:
                continue

            ts = number(row["time_created"])
            if ts > 10_000_000_000:
                ts = round(ts / 1000)
            day = date_string(dt.datetime.fromtimestamp(ts).date()) if ts > 0 else today
            session_id = str(row["id"])

            total_sessions.add(session_id)
            total_prompts += 1

            bucket = model_usage.setdefault(model, {
                "inputTokens": 0,
                "outputTokens": 0,
                "cacheReadInputTokens": 0,
                "cacheCreationInputTokens": 0,
            })
            bucket["inputTokens"] += input_t + reasoning_t
            bucket["outputTokens"] += output_t
            bucket["cacheReadInputTokens"] += cache_read
            bucket["cacheCreationInputTokens"] += cache_write

            if day in recent:
                recent[day]["messageCount"] += total

            if day == today:
                today_prompts += 1
                today_sessions.add(session_id)
                today_total_tokens += total
                today_tokens_by_model[model] = today_tokens_by_model.get(model, 0) + total

        conn.close()
    except Exception as exc:
        print(f"Error querying opencode db: {exc}", file=sys.stderr)
        return empty_result()

    return {
        "schemaVersion": 1,
        "todayPrompts": today_prompts,
        "todaySessions": len(today_sessions),
        "todayTotalTokens": today_total_tokens,
        "todayTokensByModel": today_tokens_by_model,
        "recentDays": [recent[day] for day in recent_dates],
        "modelUsage": model_usage,
        "totalPrompts": total_prompts,
        "totalSessions": len(total_sessions),
        "ready": True,
        "hasLocalStats": True,
    }


def empty_result() -> dict[str, Any]:
    recent_dates = recent_date_strings()
    return {
        "schemaVersion": 1,
        "todayPrompts": 0,
        "todaySessions": 0,
        "todayTotalTokens": 0,
        "todayTokensByModel": {},
        "recentDays": [{"date": day, "messageCount": 0} for day in recent_dates],
        "modelUsage": {},
        "totalPrompts": 0,
        "totalSessions": 0,
        "ready": True,
        "hasLocalStats": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("db_path", nargs="?", default="~/.local/share/opencode/opencode.db")
    args = parser.parse_args()

    db_path = expand_path(args.db_path)
    summary = scan(db_path)
    print(json.dumps(summary, separators=(",", ":"), sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
