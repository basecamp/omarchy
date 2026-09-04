#!/usr/bin/python3
# omarchy:summary=Print an OpenCode usage record for one route as JSON
# omarchy:args=--route <zen|go>
# omarchy:hidden=true
"""Collect OpenCode usage for one route (zen or go) into a display-ready
JSON record.

Usage: opencode-usage-base.py --route zen
       opencode-usage-base.py --route go

Local stats come from Pi session transcripts and the opencode CLI database.
There is no limits/tier RPC (OpenCode has no public API for rate limits), so
the record carries empty limits and no tier label.

This script is invoked by the omarchy-agent-usage-opencode-{zen,go} wrapper
scripts. The agents panel only ever reads the JSON this prints.
"""

import argparse
import json
import os
import shutil
import subprocess
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROUTE_PROVIDERS = {
  "zen": {"opencode", "opencode-zen-openai"},
  "go": {"opencode-go"},
}


def local_day(value):
  if value is None:
    return datetime.now().strftime("%Y-%m-%d")
  if isinstance(value, (int, float)):
    if value > 10_000_000_000:
      value = value / 1000
    return datetime.fromtimestamp(value).strftime("%Y-%m-%d")
  text = str(value)
  try:
    if text.endswith("Z"):
      dt = datetime.fromisoformat(text[:-1] + "+00:00")
    else:
      dt = datetime.fromisoformat(text)
    if dt.tzinfo is not None:
      dt = dt.astimezone()
    return dt.strftime("%Y-%m-%d")
  except Exception:
    return datetime.now().strftime("%Y-%m-%d")


def number(value):
  try:
    return int(value or 0)
  except Exception:
    return 0


def model_name(raw):
  value = str(raw or "opencode")
  return value if value else "opencode"


def runtime_env():
  home = str(Path.home())
  path_parts = [
    os.environ.get("PATH", ""),
    f"{home}/.local/bin",
    f"{home}/.npm-global/bin",
    f"{home}/.local/share/mise/shims",
  ]
  env = os.environ.copy()
  env["PATH"] = os.pathsep.join(part for part in path_parts if part)
  return env


ENV = runtime_env()


def find_command(name):
  return shutil.which(name, path=ENV.get("PATH"))


def main():
  parser = argparse.ArgumentParser()
  parser.add_argument("--route", required=True, choices=("zen", "go"))
  args = parser.parse_args()
  route = args.route

  AGENT_ID = f"opencode-{route}"
  AGENT_NAME = {"zen": "OpenCode Zen", "go": "OpenCode Go"}[route]
  AGENT_TIER = {"zen": "API", "go": "Subscription"}[route]
  ROUTE_PROVIDERS_SET = ROUTE_PROVIDERS[route]

  now = datetime.now()
  today = now.strftime("%Y-%m-%d")
  recent_dates = [(now - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(6, -1, -1)]

  recent_by_day = {day: {"date": day, "messageCount": 0} for day in recent_dates}
  today_tokens_by_model = {}
  model_usage = {}
  today_sessions = set()
  active_dates = set()
  total_sessions = set()
  total_prompts = 0
  today_prompts = 0
  today_total_tokens = 0
  seen_pi_messages = set()


  def add_usage(day, session_key, model, input_tokens, output_tokens, cache_read, cache_write, is_prompt=True):
    nonlocal today_prompts, today_total_tokens, total_prompts
    total = input_tokens + output_tokens + cache_read + cache_write
    if is_prompt:
      total_prompts += 1
      if day == today:
        today_prompts += 1
    total_sessions.add(session_key)
    active_dates.add(day)

    bucket = model_usage.setdefault(model, {
      "inputTokens": 0,
      "outputTokens": 0,
      "cacheReadInputTokens": 0,
      "cacheCreationInputTokens": 0,
    })
    bucket["inputTokens"] += input_tokens
    bucket["outputTokens"] += output_tokens
    bucket["cacheReadInputTokens"] += cache_read
    bucket["cacheCreationInputTokens"] += cache_write

    if day in recent_by_day:
      recent_by_day[day]["messageCount"] += total

    if day == today:
      today_sessions.add(session_key)
      today_total_tokens += total
      today_tokens_by_model[model] = today_tokens_by_model.get(model, 0) + total


  def add_cli_day(day, session_keys, model, input_tokens, output_tokens, reasoning_tokens, cache_read, cache_write):
    nonlocal today_total_tokens, today_prompts, total_prompts
    total = input_tokens + output_tokens + reasoning_tokens + cache_read + cache_write

    if model:
      bucket = model_usage.setdefault(model, {
        "inputTokens": 0,
        "outputTokens": 0,
        "cacheReadInputTokens": 0,
        "cacheCreationInputTokens": 0,
      })
      bucket["inputTokens"] += input_tokens
      bucket["outputTokens"] += output_tokens + reasoning_tokens
      bucket["cacheReadInputTokens"] += cache_read
      bucket["cacheCreationInputTokens"] += cache_write

    if day in recent_by_day:
      recent_by_day[day]["messageCount"] += total
      for key in session_keys:
        total_sessions.add(key)
        if day == today:
          today_sessions.add(key)

    else:
      # Outside the 7-day window — still count sessions and active days.
      for key in session_keys:
        total_sessions.add(key)

    if day == today:
      today_total_tokens += total
      if model:
        today_tokens_by_model[model] = today_tokens_by_model.get(model, 0) + total

    active_dates.add(day)


  # -------------------------------------------------------------- Pi sessions

  def scan_pi_sessions():
    root = Path.home() / ".pi" / "agent" / "sessions"
    if not root.exists():
      return
    try:
      rg = find_command("rg") or "rg"
      proc = subprocess.Popen(
        [rg, "--json", "-e", '"provider":"opencode"',
         "-e", '"provider":"opencode-go"',
         "-e", '"provider":"opencode-zen-openai"',
         str(root)],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        errors="replace",
        env=ENV,
      )
    except FileNotFoundError:
      return

    assert proc.stdout is not None
    for raw in proc.stdout:
      try:
        event = json.loads(raw)
        if event.get("type") != "match":
          continue
        line = event.get("data", {}).get("lines", {}).get("text", "")
        path = event.get("data", {}).get("path", {}).get("text", "pi-session")
        entry = json.loads(line)
      except Exception:
        continue

      if entry.get("type") != "message":
        continue
      message = entry.get("message") or {}
      if message.get("role") != "assistant":
        continue
      provider = str(message.get("provider") or "")
      if provider not in ROUTE_PROVIDERS_SET:
        continue

      message_key = path + ":" + str(entry.get("id") or "")
      if message_key in seen_pi_messages:
        continue
      seen_pi_messages.add(message_key)

      usage = message.get("usage") or {}
      if not usage:
        continue
      total = number(usage.get("totalTokens"))
      input_tokens = number(usage.get("input"))
      output_tokens = number(usage.get("output"))
      cache_read = number(usage.get("cacheRead"))
      cache_write = number(usage.get("cacheWrite"))
      if total and not (input_tokens or output_tokens or cache_read or cache_write):
        input_tokens = total
      if not (input_tokens or output_tokens or cache_read or cache_write):
        continue

      day = local_day(entry.get("timestamp") or message.get("timestamp"))
      session_key = path
      add_usage(day, session_key, model_name(message.get("model")),
                input_tokens, output_tokens, cache_read, cache_write)

    try:
      proc.wait(timeout=1)
    except Exception:
      proc.kill()


  # ---------------------------------------------------------- opencode CLI DB

  def db_rows():
    opencode = find_command("opencode")
    if not opencode:
      return None
    query = (
      "SELECT date(m.time_created/1000,'unixepoch','localtime') AS day, "
      "CASE json_extract(m.data,'$.providerID') "
      "  WHEN 'opencode' THEN 'zen' "
      "  WHEN 'opencode-zen-openai' THEN 'zen' "
      "  WHEN 'opencode-go' THEN 'go' "
      "END AS route, "
      "json_extract(m.data,'$.modelID') AS model, "
      "group_concat(DISTINCT m.session_id) AS session_ids, "
      "sum(json_extract(m.data,'$.tokens.input')) AS input, "
      "sum(json_extract(m.data,'$.tokens.output')) AS output, "
      "sum(json_extract(m.data,'$.tokens.reasoning')) AS reasoning, "
      "sum(json_extract(m.data,'$.tokens.cache.read')) AS cache_read, "
      "sum(json_extract(m.data,'$.tokens.cache.write')) AS cache_write "
      "FROM message m "
      "WHERE json_extract(m.data,'$.role') = 'assistant' "
      "GROUP BY day, route, model ORDER BY day"
    )
    try:
      proc = subprocess.Popen(
        [opencode, "db", query, "--format", "json"],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        errors="replace",
        env=ENV,
      )
      output, _ = proc.communicate(timeout=30)
      if proc.returncode != 0:
        return None
      rows = json.loads(output or "[]")
      return rows if isinstance(rows, list) else None
    except subprocess.TimeoutExpired:
      try:
        proc.kill()
        proc.wait()
      except Exception:
        pass
      return None
    except Exception:
      return None

  def scan_opencode_cli_db():
    rows = db_rows()
    if not rows:
      return
    for row in rows:
      route_val = str(row.get("route") or "")
      if route_val != route:
        continue
      day = str(row.get("day") or "")
      if not day:
        continue
      session_keys = ["cli:" + sid for sid in str(row.get("session_ids") or "").split(",") if sid]
      model = str(row.get("model") or "")
      input_tokens = number(row.get("input"))
      output_tokens = number(row.get("output"))
      reasoning_tokens = number(row.get("reasoning"))
      cache_read = number(row.get("cache_read"))
      cache_write = number(row.get("cache_write"))
      add_cli_day(day, session_keys, model, input_tokens, output_tokens, reasoning_tokens, cache_read, cache_write)


  # ---------------------------------------------------------------- run

  scan_pi_sessions()
  scan_opencode_cli_db()

  record = {
    "schemaVersion": 1,
    "id": AGENT_ID,
    "name": AGENT_NAME,
    "updatedAt": datetime.now(timezone.utc).isoformat(),
    "ready": True,
    "hasLocalStats": True,
    "hasPromptStats": True,
    "todayPrompts": today_prompts,
    "todaySessions": len(today_sessions),
    "todayTotalTokens": today_total_tokens,
    "todayTokensByModel": today_tokens_by_model,
    "recentDays": [recent_by_day[day] for day in recent_dates],
    "totalPrompts": total_prompts,
    "totalSessions": len(total_sessions),
    "activeDays": len(active_dates),
    "activeDates": sorted(active_dates),
    "modelUsage": model_usage,
    "retryAdvised": False,
    "limits": [],
    "tierLabel": AGENT_TIER,
    "usageStatusText": "",
    "authHelpText": "",
  }
  print(json.dumps(record, separators=(",", ":")))


if __name__ == "__main__":
  main()
