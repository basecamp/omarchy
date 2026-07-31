import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


# `dropbox-cli exclude list` prints each path through `relpath()`, so its output
# is relative to our cwd. Running from "/" makes every line a root-relative path
# that becomes absolute with a single "/" prefix — no guessing at where the
# Dropbox folder lives or what it is called.
IGNORE_LIST_CWD = "/"

IGNORE_HEADER = "excluded:"
IGNORE_EMPTY = "no directories are being ignored."


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
  # info.json is whatever is on disk, so it can decode to a list or a string
  # just as easily as an object. Check before treating it as a mapping.
  if not isinstance(info, dict):
    return {}
  for key in ("personal", "business"):
    account = info.get(key)
    if isinstance(account, dict):
      return account
  return {}


def account_path():
  account = dropbox_account(read_info())
  path = account.get("path")
  return path if isinstance(path, str) else ""


def ignore_set(dropbox_cli):
  """Absolute paths currently excluded from syncing, or None if unreadable."""
  if not dropbox_cli:
    return None
  try:
    completed = subprocess.run(
      [dropbox_cli, "exclude", "list"],
      check=False, capture_output=True, text=True, timeout=10, cwd=IGNORE_LIST_CWD)
  except (OSError, subprocess.TimeoutExpired):
    return None
  if completed.returncode != 0:
    return None

  paths = set()
  for raw in completed.stdout.splitlines():
    # Folder names may contain spaces and pipes, so only ever strip whitespace —
    # never split the line.
    line = raw.strip()
    lowered = line.lower()
    if line == "" or lowered == IGNORE_HEADER or lowered == IGNORE_EMPTY:
      continue
    if lowered.startswith("dropbox isn't") or lowered.startswith("couldn't "):
      return None
    paths.add(os.path.join("/", line))
  return paths


def subdirectory_count(path):
  count = 0
  try:
    with os.scandir(path) as entries:
      for entry in entries:
        if entry.name.startswith("."):
          continue
        try:
          if entry.is_dir(follow_symlinks=False):
            count += 1
        except OSError:
          continue
  except OSError:
    return 0
  return count


def local_subdirectories(path):
  names = []
  try:
    with os.scandir(path) as entries:
      for entry in entries:
        if entry.name.startswith("."):
          continue
        try:
          if entry.is_dir(follow_symlinks=False):
            names.append(entry.name)
        except OSError:
          continue
  except OSError:
    return None
  return names


def within(root, path):
  # Compare resolved paths: abspath alone is lexical, so a symlink parked
  # inside Dropbox and pointing elsewhere would pass the check and then be
  # walked. Listings never offer symlinks as children, but this is the stated
  # boundary and it should hold for any argument.
  try:
    return os.path.commonpath([os.path.realpath(root), os.path.realpath(path)]) == os.path.realpath(root)
  except (ValueError, OSError):
    return False


def fail(message, root=""):
  print(json.dumps({
    "ok": False,
    "error": message,
    "accountPath": root,
    "path": "",
    "parentPath": "",
    "atRoot": True,
    "folders": [],
  }))
  return 0


def list_folders(target):
  root = account_path()
  if root == "" or not os.path.isdir(root):
    return fail("Dropbox folder not found", root)

  target = os.path.abspath(os.path.expanduser(target or root))
  # Never let a bad argument walk outside the Dropbox folder.
  if not within(root, target):
    return fail("Path is outside the Dropbox folder", root)
  if not os.path.isdir(target):
    return fail("Folder is no longer available", root)

  dropbox_cli = shutil.which("dropbox-cli")
  if dropbox_cli is None:
    return fail("Dropbox CLI is not installed", root)

  excluded = ignore_set(dropbox_cli)
  if excluded is None:
    return fail("Dropbox isn't running", root)

  local = local_subdirectories(target)
  if local is None:
    return fail("Could not read folder contents", root)

  # Children of `target` come from two places: directories that exist on disk
  # (synced) and ignore-set entries parented here (excluded, so absent locally).
  # A path can briefly appear in both while the daemon is deleting it — excluded
  # wins, since that is the state the user just asked for.
  excluded_here = {path for path in excluded if os.path.dirname(path) == target}
  names = {name: os.path.join(target, name) for name in local}
  for path in excluded_here:
    names[os.path.basename(path)] = path

  folders = []
  for name in sorted(names, key=lambda value: (value.lower(), value)):
    path = names[name]
    is_excluded = path in excluded_here
    # The CLI has no remote listing, so an excluded folder's children are
    # unknowable — it stays a toggle-only leaf until it is synced again.
    children = 0 if is_excluded else subdirectory_count(path)
    folders.append({
      "name": name,
      "path": path,
      "excluded": is_excluded,
      "browsable": not is_excluded and children > 0,
      "childCount": children,
    })

  print(json.dumps({
    "ok": True,
    "error": "",
    "accountPath": root,
    "path": target,
    "parentPath": "" if target == root else os.path.dirname(target),
    "atRoot": target == root,
    "folders": folders,
  }))
  return 0


def main():
  args = sys.argv[1:]
  command = args[0] if args else "list"
  if command != "list":
    return fail("Unknown command: " + command)
  return list_folders(args[1] if len(args) > 1 else "")


if __name__ == "__main__":
  sys.exit(main())
