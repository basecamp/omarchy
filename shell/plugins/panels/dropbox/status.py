import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
import heapq
from pathlib import Path


PLAN_QUOTAS = {
  "basic": 2_000_000_000,
  "plus": 2_000_000_000_000,
  "pro": 3_000_000_000_000,
  "professional": 3_000_000_000_000,
  "essentials": 3_000_000_000_000,
}


def read_api_token():
  # The Dropbox API token is read from the environment only, so no secret is
  # stored in the panel config or this repository.
  token = os.environ.get("DROPBOX_API_TOKEN", "").strip()
  return token or None


def fetch_api_usage(token):
  if token is None:
    return None
  request = urllib.request.Request(
    "https://api.dropboxapi.com/2/users/get_space_usage",
    method="POST",
    headers={"Authorization": "Bearer " + token},
  )
  try:
    with urllib.request.urlopen(request, timeout=5) as response:
      body = json.loads(response.read().decode("utf-8"))
  except (OSError, ValueError, urllib.error.URLError):
    return None
  allocation = body.get("allocation", {})
  try:
    allocated = int(allocation.get("allocated", 0))
    used = int(body.get("used", 0))
  except (TypeError, ValueError):
    return None
  if allocated <= 0 or used < 0:
    return None
  return used, allocated


def read_info():
  info_path = Path.home() / ".dropbox" / "info.json"
  if not info_path.exists():
    return {}
  try:
    with info_path.open("r", encoding="utf-8") as handle:
      return json.load(handle)
  except (OSError, json.JSONDecodeError):
    return {}


def dropbox_account(info):
  for key in ("personal", "business"):
    account = info.get(key)
    if isinstance(account, dict):
      return account
  return {}


def command_output(command):
  try:
    completed = subprocess.run(command, check=False, capture_output=True, text=True, timeout=4)
  except (OSError, subprocess.TimeoutExpired):
    return 1, ""
  return completed.returncode, (completed.stdout + completed.stderr).strip()


def scan_dropbox(path, limit):
  total = 0
  counter = 0
  recent = []
  try:
    for root, dirs, files in os.walk(path):
      dirs[:] = [name for name in dirs if not os.path.islink(os.path.join(root, name))]
      for name in files:
        file_path = os.path.join(root, name)
        if os.path.islink(file_path):
          continue
        try:
          stat = os.stat(file_path)
        except OSError:
          continue
        total += stat.st_size
        rel = os.path.relpath(file_path, path)
        folder = os.path.dirname(rel)
        row = {
          "name": name,
          "path": file_path,
          "folder": "/" if folder in ("", ".") else folder,
          "modifiedTs": int(stat.st_mtime),
          "sizeBytes": stat.st_size,
        }
        counter += 1
        entry = (row["modifiedTs"], counter, row)
        if len(recent) < limit:
          heapq.heappush(recent, entry)
        else:
          heapq.heappushpop(recent, entry)
  except OSError:
    return 0, []
  rows = [entry[2] for entry in sorted(recent, reverse=True)]
  return total, rows


def main():
  limit = 25
  if len(sys.argv) > 1:
    try:
      limit = max(1, min(100, int(sys.argv[1])))
    except ValueError:
      limit = 25

  dropbox_cli = shutil.which("dropbox-cli")
  info = read_info()
  account = dropbox_account(info)
  account_path = account.get("path") if isinstance(account.get("path"), str) else ""
  plan = account.get("subscription_type") if isinstance(account.get("subscription_type"), str) else ""
  authenticated = account_path != "" and Path(account_path).exists()

  running = False
  status_text = "Not installed"
  if dropbox_cli:
    status_exit, status_output = command_output([dropbox_cli, "status"])
    status_text = status_output if status_exit == 0 and status_output else "Stopped"
    lowered = status_text.lower()
    stopped = "not running" in lowered or "isn't running" in lowered or lowered == "stopped"
    running = status_exit == 0 and status_output != "" and not stopped

  used, files = scan_dropbox(account_path, limit) if authenticated else (0, [])

  # Prefer server-reported usage and quota when an API token is configured:
  # plan-based quotas ignore bonus/referral space, so e.g. a Basic account
  # can hold more than the base 2 GB and used can exceed quota locally.
  api_usage = fetch_api_usage(read_api_token())
  if api_usage is not None:
    used, quota = api_usage
  else:
    quota = PLAN_QUOTAS.get(plan.lower(), 0)

  usage_percent = (used / quota * 100) if quota > 0 else 0

  print(json.dumps({
    "ok": True,
    "installed": dropbox_cli is not None,
    "running": running,
    "authenticated": authenticated,
    "statusText": status_text,
    "accountPath": account_path,
    "plan": plan,
    "usedBytes": used,
    "quotaBytes": quota,
    "usagePercent": usage_percent,
    "quotaKnown": quota > 0,
    "files": files,
  }))


if __name__ == "__main__":
  main()
