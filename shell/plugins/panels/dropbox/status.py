import json
import os
import shutil
import subprocess
import sys
import heapq
from pathlib import Path


PLAN_QUOTAS = {
  "basic": 2_000_000_000,
  "plus": 2_000_000_000_000,
  "pro": 3_000_000_000_000,
  "professional": 3_000_000_000_000,
  "essentials": 3_000_000_000_000,
}


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
  # One scandir per directory and one lstat per file. The type checks come
  # from the directory entry itself, so a large folder costs a fraction of
  # what os.walk plus per-file islink/stat/relpath did (~1s vs ~5s for
  # 470k files).
  root = str(path).rstrip("/") or "/"
  prefix_len = len(root) + 1
  total = 0
  counter = 0
  recent = []
  stack = [root]
  while stack:
    folder_path = stack.pop()
    try:
      entries = os.scandir(folder_path)
    except OSError:
      continue
    folder = folder_path[prefix_len:] or "/"
    with entries:
      for entry in entries:
        try:
          if entry.is_symlink():
            continue
          if entry.is_dir(follow_symlinks=False):
            stack.append(entry.path)
            continue
          stat = entry.stat(follow_symlinks=False)
        except OSError:
          continue
        total += stat.st_size
        row = {
          "name": entry.name,
          "path": entry.path,
          "folder": folder,
          "modifiedTs": int(stat.st_mtime),
          "sizeBytes": stat.st_size,
        }
        counter += 1
        entry_key = (row["modifiedTs"], counter, row)
        if len(recent) < limit:
          heapq.heappush(recent, entry_key)
        else:
          heapq.heappushpop(recent, entry_key)
  rows = [entry_key[2] for entry_key in sorted(recent, reverse=True)]
  return total, rows


def main():
  limit = 25
  # "quick" skips the Dropbox folder walk (seconds on large folders) and only
  # reports daemon state, for the fast re-polls after a pause/resume.
  quick = "--quick" in sys.argv[1:]
  args = [a for a in sys.argv[1:] if a != "--quick"]
  if args:
    try:
      limit = max(1, min(100, int(args[0])))
    except ValueError:
      limit = 25

  dropbox_cli = shutil.which("dropbox-cli")
  info = read_info()
  account = dropbox_account(info)
  account_path = account.get("path") if isinstance(account.get("path"), str) else ""
  plan = account.get("subscription_type") if isinstance(account.get("subscription_type"), str) else ""
  quota = PLAN_QUOTAS.get(plan.lower(), 0)
  authenticated = account_path != "" and Path(account_path).exists()

  running = False
  status_text = "Not installed"
  if dropbox_cli:
    status_exit, status_output = command_output([dropbox_cli, "status"])
    status_text = status_output if status_exit == 0 and status_output else "Stopped"
    lowered = status_text.lower()
    stopped = "not running" in lowered or "isn't running" in lowered or lowered == "stopped"
    running = status_exit == 0 and status_output != "" and not stopped

  used, files = scan_dropbox(account_path, limit) if authenticated and not quick else (0, [])
  usage_percent = (used / quota * 100) if quota > 0 else 0

  print(json.dumps({
    "ok": True,
    "quick": quick,
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
