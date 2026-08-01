import json
import os
import re
import ssl
import subprocess
import sys
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path


def number(value):
  try:
    return int(value or 0)
  except Exception:
    return 0


def float_value(value):
  try:
    return float(value)
  except Exception:
    return None


def local_day_from_ms(ts_ms):
  try:
    seconds = float(ts_ms) / 1000.0 if float(ts_ms) > 10_000_000_000 else float(ts_ms)
    return datetime.fromtimestamp(seconds).strftime("%Y-%m-%d")
  except Exception:
    return datetime.now().strftime("%Y-%m-%d")


def scan_local_stats():
  history = Path.home() / ".gemini" / "antigravity-cli" / "history.jsonl"
  now = datetime.now()
  today = now.strftime("%Y-%m-%d")
  recent_dates = [(now - timedelta(days=offset)).strftime("%Y-%m-%d") for offset in range(6, -1, -1)]

  today_prompts = 0
  total_prompts = 0
  today_sessions = set()
  total_sessions = set()
  active_days = set()

  # Track prompt count by day for the recent 7 days
  recent_days_map = {date: {"date": date, "messageCount": 0} for date in recent_dates}

  if history.exists():
    try:
      with history.open("r", encoding="utf-8", errors="replace") as handle:
        for raw in handle:
          try:
            entry = json.loads(raw)
          except Exception:
            continue
          ts = entry.get("timestamp")
          if ts is None:
            continue
          day = local_day_from_ms(ts)
          conversation = entry.get("conversationId") or f"prompt-{day}-{ts}"
          total_prompts += 1
          total_sessions.add(conversation)
          active_days.add(day)

          if day in recent_days_map:
            recent_days_map[day]["messageCount"] += 1

          if day == today:
            today_prompts += 1
            today_sessions.add(conversation)
    except Exception:
      pass

  return {
    "todayPrompts": today_prompts,
    "todaySessions": len(today_sessions),
    "todayTotalTokens": 0,
    "todayTokensByModel": {},
    # Populate recentDays with local daily prompt counts. While the UI refers
    # to this as "TOKENS BY DAY", displaying prompt counts allows drawing
    # the weekly activity bar chart for Antigravity instead of hiding it.
    "recentDays": [recent_days_map[date] for date in recent_dates],
    "modelUsage": {},
    "totalPrompts": total_prompts,
    "totalSessions": len(total_sessions),
    "activeDays": len(active_days),
    "activeDates": sorted(active_days),
  }


def parse_arg(args, name):
  for index, arg in enumerate(args):
    text = arg.decode("utf-8", errors="replace")
    if text == name and index + 1 < len(args):
      return args[index + 1].decode("utf-8", errors="replace")
    if text.startswith(name + "="):
      return text[len(name) + 1:]
  return None


def find_language_server():
  for entry in os.scandir("/proc"):
    if not entry.name.isdigit():
      continue
    cmdline_path = Path(entry.path) / "cmdline"
    try:
      raw = cmdline_path.read_bytes()
    except OSError:
      continue
    args = raw.split(b"\x00")
    cmdline = " ".join(a.decode("utf-8", errors="replace") for a in args).lower()
    if "language_server" not in cmdline or "antigravity" not in cmdline:
      continue
    csrf = parse_arg(args, "--csrf_token")
    extension_port = parse_arg(args, "--extension_server_port")
    return entry.name, csrf, extension_port
  return None, None, None


def listening_ports_for(pid):
  ports = []
  try:
    result = subprocess.run(["ss", "-tlnp"], capture_output=True, text=True, timeout=10)
    for line in result.stdout.splitlines():
      if f"pid={pid}," not in line:
        continue
      for match in re.finditer(r":(\d+)(?:\s+\(LISTEN\))?\s*$", line):
        ports.append(match.group(1))
  except Exception:
    pass

  if not ports:
    try:
      result = subprocess.run(["lsof", "-nP", "-a", "-iTCP", "-sTCP:LISTEN", "-p", pid],
                              capture_output=True, text=True, timeout=10)
      for line in result.stdout.splitlines()[1:]:
        for match in re.finditer(r":(\d+)$", line):
          ports.append(match.group(1))
    except Exception:
      pass

  seen = set()
  ordered = []
  for port in ports:
    if port not in seen:
      seen.add(port)
      ordered.append(port)
  return ordered


def http_post(scheme, port, path, csrf, payload, timeout=4):
  url = "{}://127.0.0.1:{}{}".format(scheme, port, path)
  data = json.dumps(payload).encode("utf-8")
  request = urllib.request.Request(url, data=data, method="POST")
  request.add_header("X-Codeium-Csrf-Token", csrf or "")
  request.add_header("Connect-Protocol-Version", "1")
  request.add_header("Content-Type", "application/json")
  context = ssl.create_default_context()
  context.check_hostname = False
  context.verify_mode = ssl.CERT_NONE
  with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
    return response.status, response.read()


def parse_limits(payload):
  result = {
    "rateLimitPercent": -1,
    "rateLimitLabel": "",
    "rateLimitResetAt": "",
    "secondaryRateLimitPercent": -1,
    "secondaryRateLimitLabel": "",
    "secondaryRateLimitResetAt": "",
    "tierLabel": "",
  }
  if not isinstance(payload, dict):
    return result

  user_status = payload.get("userStatus")
  if not isinstance(user_status, dict):
    user_status = {}
  plan_status = user_status.get("planStatus")
  if not isinstance(plan_status, dict):
    plan_status = {}
  plan_info = plan_status.get("planInfo")
  if not isinstance(plan_info, dict):
    plan_info = {}

  plan = plan_info.get("planName") or user_status.get("planName") or payload.get("planName")
  result["tierLabel"] = str(plan) if plan else ""

  config_data = user_status.get("cascadeModelConfigData")
  if not isinstance(config_data, dict):
    config_data = payload.get("cascadeModelConfigData")
  if not isinstance(config_data, dict):
    config_data = {}
  configs = config_data.get("clientModelConfigs")
  if not isinstance(configs, list):
    configs = []

  def usage_percent(available_key, monthly_key, model_markers):
    monthly = float_value(plan_info.get(monthly_key))
    available = float_value(plan_status.get(available_key))
    if monthly and available is not None and available >= 0:
      return 1.0 - (available / monthly)
    fractions = []
    for model in configs:
      label = str(model.get("modelLabel") or "")
      quota = model.get("quotaInfo")
      remaining = float_value(quota.get("remainingFraction")) if isinstance(quota, dict) else None
      if remaining is None:
        continue
      lowered = label.lower()
      if any(marker in lowered for marker in model_markers):
        fractions.append(remaining)
    if fractions:
      return 1.0 - min(fractions)
    return -1

  primary = usage_percent("availablePromptCredits", "monthlyPromptCredits", ["claude", "opus", "sonnet"])
  secondary = usage_percent("availableFlowCredits", "monthlyFlowCredits", ["pro", "flash", "gemini"])

  if primary >= 0:
    result["rateLimitPercent"] = min(1.0, max(0.0, primary))
    result["rateLimitLabel"] = "Prompt credits"
  if secondary >= 0:
    result["secondaryRateLimitPercent"] = min(1.0, max(0.0, secondary))
    result["secondaryRateLimitLabel"] = "Flow credits"

  for reset_key in ("resetAt", "resetTime", "resetsAt"):
    if plan_status.get(reset_key):
      result["rateLimitResetAt"] = str(plan_status[reset_key])
      break
  return result


def fetch_limits():
  result = {
    "rateLimitPercent": -1,
    "rateLimitLabel": "",
    "rateLimitResetAt": "",
    "secondaryRateLimitPercent": -1,
    "secondaryRateLimitLabel": "",
    "secondaryRateLimitResetAt": "",
    "tierLabel": "",
    "usageStatusText": "",
    "authHelpText": "",
  }

  pid, csrf, extension_port = find_language_server()
  if not pid:
    result["usageStatusText"] = "Antigravity IDE not running"
    result["authHelpText"] = "Open the Antigravity IDE to load usage limits. Local agy stats are still shown."
    return result
  if not csrf:
    result["usageStatusText"] = "Antigravity limits unavailable"
    result["authHelpText"] = "Couldn't find the language server's CSRF token. Restart Antigravity."
    return result

  ports = listening_ports_for(pid)
  if extension_port:
    ports = ports + [extension_port]
  seen = set()
  ordered = []
  for port in ports:
    if port not in seen:
      seen.add(port)
      ordered.append(port)

  connect = None
  for port in ordered:
    for scheme in ("https", "http"):
      try:
        status, _ = http_post(scheme, port, "/exa.language_server_pb.LanguageServerService/GetUnleashData", csrf, {})
        if status < 300:
          connect = (scheme, port)
          break
      except Exception:
        continue
    if connect:
      break

  if not connect:
    result["usageStatusText"] = "Antigravity limits unavailable"
    result["authHelpText"] = "Couldn't reach the Antigravity language server. It may still be starting up."
    return result

  scheme, port = connect
  try:
    status, body = http_post(
      scheme, port,
      "/exa.language_server_pb.LanguageServerService/GetUserStatus",
      csrf,
      {"metadata": {"ideName": "antigravity", "extensionName": "antigravity", "locale": "en", "ideVersion": "unknown"}},
      timeout=6,
    )
    if status >= 300:
      raise RuntimeError("HTTP {}".format(status))
    payload = json.loads(body.decode("utf-8", errors="replace"))
  except Exception as exc:
    result["usageStatusText"] = "Antigravity limits unavailable"
    result["authHelpText"] = "GetUserStatus failed: {}".format(exc)
    return result

  result.update(parse_limits(payload))
  return result


def main():
  out = {
    "ready": True,
    "hasLocalStats": True,
  }
  out.update(scan_local_stats())
  out.update(fetch_limits())
  print(json.dumps(out, separators=(",", ":")))
  return 0


if __name__ == "__main__":
  sys.exit(main())
