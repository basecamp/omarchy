import json
import os
import select
import shutil
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path


def local_day(value):
  if value is None:
    return datetime.now().strftime("%Y-%m-%d")
  if isinstance(value, (int, float)):
    # pi message timestamps are milliseconds; Codex timestamps are usually seconds.
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
  value = str(raw or "codex")
  return value if value else "codex"


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


now = datetime.now()
today = now.strftime("%Y-%m-%d")
recent_dates = [(now - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(6, -1, -1)]
recent_set = set(recent_dates)
recent = {day: {"date": day, "messageCount": 0} for day in recent_dates}
today_tokens_by_model = {}
model_usage = {}
sessions_by_day = {day: set() for day in recent_dates}
today_sessions = set()

today_prompts = 0
today_total_tokens = 0
total_prompts = 0
total_sessions = set()
seen_pi_messages = set()
usage_status = ""
usage_help = ""


def add_usage(day, session_key, model, input_tokens, output_tokens, cache_read, cache_write):
  global today_prompts, today_total_tokens, total_prompts
  total = input_tokens + output_tokens + cache_read + cache_write
  total_prompts += 1
  total_sessions.add(session_key)

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

  if day in recent:
    recent[day]["messageCount"] += total
    sessions_by_day[day].add(session_key)

  if day == today:
    today_prompts += 1
    today_sessions.add(session_key)
    today_total_tokens += total
    today_tokens_by_model[model] = today_tokens_by_model.get(model, 0) + total


def scan_pi_sessions():
  root = Path.home() / ".pi" / "agent" / "sessions"
  if not root.exists():
    return
  try:
    rg = find_command("rg") or "rg"
    proc = subprocess.Popen(
      [rg, "--json", "-e", '"provider":"openai-codex"', "-e", '"api":"openai-codex"', str(root)],
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
    message_key = path + ":" + str(entry.get("id") or "")
    if message_key in seen_pi_messages:
      continue
    seen_pi_messages.add(message_key)
    message = entry.get("message") or {}
    if message.get("role") != "assistant":
      continue
    provider = str(message.get("provider") or "")
    api = str(message.get("api") or "")
    if provider != "openai-codex" and not api.startswith("openai-codex"):
      continue

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
    add_usage(day, session_key, model_name(message.get("model")), input_tokens, output_tokens, cache_read, cache_write)

  try:
    proc.wait(timeout=1)
  except Exception:
    proc.kill()


def scan_native_codex_sessions():
  codex_home = Path(os.environ.get("CODEX_HOME") or (Path.home() / ".codex"))
  roots = [codex_home / "sessions", codex_home / "archived_sessions"]
  files = []
  cutoff = time.time() - 30 * 24 * 60 * 60
  for root in roots:
    if not root.exists():
      continue
    for path in root.rglob("*.jsonl"):
      try:
        if path.stat().st_mtime >= cutoff:
          files.append(path)
      except OSError:
        pass

  for path in files:
    current_model = "codex"
    try:
      with path.open(errors="replace") as handle:
        for raw in handle:
          try:
            entry = json.loads(raw)
          except Exception:
            continue
          if entry.get("type") == "turn_context":
            payload = entry.get("payload") or {}
            current_model = model_name(payload.get("model") or payload.get("model_slug") or current_model)
            continue
          payload = entry.get("payload") or entry
          if entry.get("type") == "response_item" and isinstance(payload, dict):
            payload = payload.get("payload") or payload
          if not isinstance(payload, dict):
            continue
          if payload.get("type") != "token_count":
            continue
          info = payload.get("info") or {}
          usage = info.get("total_token_usage") or {}
          input_tokens = number(usage.get("input_tokens"))
          output_tokens = number(usage.get("output_tokens")) + number(usage.get("reasoning_output_tokens"))
          cache_read = number(usage.get("cached_input_tokens"))
          cache_write = 0
          if not (input_tokens or output_tokens or cache_read):
            continue
          day = local_day(entry.get("timestamp") or path.stat().st_mtime)
          add_usage(day, str(path), current_model, input_tokens, output_tokens, cache_read, cache_write)
    except Exception:
      continue


def rpc_request(proc, request_id, method, params=None, timeout=8):
  payload = {"id": request_id, "method": method, "params": params or {}}
  proc.stdin.write(json.dumps(payload) + "\n")
  proc.stdin.flush()
  deadline = time.time() + timeout
  while time.time() < deadline:
    ready, _, _ = select.select([proc.stdout], [], [], 0.25)
    if not ready:
      continue
    line = proc.stdout.readline()
    if not line:
      break
    try:
      message = json.loads(line)
    except Exception:
      continue
    if message.get("id") == request_id:
      return message
  raise TimeoutError(method)


def fetch_codex_rpc():
  result = {
    "rateLimitPercent": -1,
    "rateLimitLabel": "",
    "rateLimitResetAt": "",
    "secondaryRateLimitPercent": -1,
    "secondaryRateLimitLabel": "",
    "secondaryRateLimitResetAt": "",
    "tierLabel": "",
  }
  codex = find_command("codex")
  if not codex:
    result["usageStatusText"] = "Codex unavailable"
    result["authHelpText"] = "codex not found in PATH"
    return result

  try:
    proc = subprocess.Popen(
      [codex, "-s", "read-only", "-a", "untrusted", "app-server"],
      stdin=subprocess.PIPE,
      stdout=subprocess.PIPE,
      stderr=subprocess.DEVNULL,
      text=True,
      env=ENV,
    )
  except Exception as exc:
    result["usageStatusText"] = "Codex unavailable"
    result["authHelpText"] = str(exc)
    return result

  try:
    rpc_request(proc, 1, "initialize", {"clientInfo": {"name": "omarchy-model-usage", "version": "1"}}, timeout=8)
    proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
    proc.stdin.flush()
    account_msg = rpc_request(proc, 2, "account/read", timeout=4)
    limits_msg = rpc_request(proc, 3, "account/rateLimits/read", timeout=4)

    account = (account_msg.get("result") or {}).get("account") or {}
    limits = (limits_msg.get("result") or {}).get("rateLimits") or {}
    plan = limits.get("planType") or account.get("planType") or account.get("type") or ""
    result["tierLabel"] = str(plan) if plan else ""

    def fill(prefix, window):
      if not isinstance(window, dict):
        return
      used = window.get("usedPercent")
      if used is not None:
        result[prefix + "Percent"] = float(used) / 100.0
      mins = number(window.get("windowDurationMins"))
      if mins:
        if mins == 10080:
          result[prefix + "Label"] = "Weekly (7-day)"
        elif mins % 60 == 0:
          result[prefix + "Label"] = f"{mins // 60}h window"
        else:
          result[prefix + "Label"] = f"{mins}m window"
      reset = window.get("resetsAt")
      if reset:
        result[prefix + "ResetAt"] = datetime.fromtimestamp(number(reset), timezone.utc).isoformat()

    fill("rateLimit", limits.get("primary"))
    fill("secondaryRateLimit", limits.get("secondary"))
  except Exception as exc:
    result["usageStatusText"] = "Codex limits unavailable"
    result["authHelpText"] = str(exc)
  finally:
    try:
      proc.terminate()
      proc.wait(timeout=1)
    except Exception:
      try:
        proc.kill()
      except Exception:
        pass
  return result


scan_pi_sessions()
scan_native_codex_sessions()
rpc = fetch_codex_rpc()

out = {
  "ready": True,
  "hasLocalStats": True,
  "todayPrompts": today_prompts,
  "todaySessions": len(today_sessions),
  "todayTotalTokens": today_total_tokens,
  "todayTokensByModel": today_tokens_by_model,
  "recentDays": [recent[day] for day in recent_dates],
  "totalPrompts": total_prompts,
  "totalSessions": len(total_sessions),
  "modelUsage": model_usage,
  "usageStatusText": usage_status,
  "authHelpText": usage_help,
}
out.update(rpc)
print(json.dumps(out, separators=(",", ":")))
