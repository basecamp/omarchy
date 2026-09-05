echo "Assign the Subscribe to Feeds shortcut to existing browser profiles"

# Chromium only applies a manifest's suggested shortcut when it first installs
# an extension. Subscribe to Feeds was added later to the already-installed
# Omarchy Browser Actions extension, so existing profiles need the new command
# registered explicitly. Preserve a user's remap and never take a shortcut that
# another command already owns.

pinned_id="bgpiichlckmfanooecilcjemknkcpngb"
accelerator="linux:Alt+Shift+F"
suggested_key="Alt+Shift+F"
backup_suffix=".omarchy-feed-shortcut.bak"

repair_py=$(cat <<'PY'
import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
pinned_id = sys.argv[2]
accelerator = sys.argv[3]
suggested_key = sys.argv[4]
backup_suffix = sys.argv[5]
mode = sys.argv[6]

try:
    preferences = json.loads(path.read_text())
except (OSError, ValueError):
    sys.exit(1)

extensions = preferences.setdefault("extensions", {})
commands = extensions.setdefault("commands", {})
settings = extensions.setdefault("settings", {})

already_bound = any(
    command.get("command_name") == "subscribe-feed"
    and command.get("extension") == pinned_id
    for command in commands.values()
)
slot_available = accelerator not in commands

if mode == "check":
    sys.exit(0 if not already_bound and slot_available else 1)

if already_bound or not slot_available:
    sys.exit(0)

commands[accelerator] = {
    "command_name": "subscribe-feed",
    "extension": pinned_id,
    "global": False,
}

extension_commands = settings.setdefault(pinned_id, {}).setdefault("commands", {})
command_settings = extension_commands.setdefault("subscribe-feed", {})
command_settings["suggested_key"] = suggested_key
command_settings["was_assigned"] = True

backup = path.with_name(path.name + backup_suffix)
shutil.copy2(path, backup)

fd, temporary_name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
try:
    with os.fdopen(fd, "w") as temporary:
        json.dump(preferences, temporary, separators=(",", ":"))
        temporary.flush()
        os.fsync(temporary.fileno())
    shutil.copystat(path, temporary_name)
    os.replace(temporary_name, path)
finally:
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
PY
)

profile_roots=(
  "$HOME/.config/chromium"
  "$HOME/.config/google-chrome"
  "$HOME/.config/google-chrome-beta"
  "$HOME/.config/google-chrome-unstable"
  "$HOME/.config/BraveSoftware/Brave-Browser"
  "$HOME/.config/BraveSoftware/Brave-Browser-Beta"
  "$HOME/.config/BraveSoftware/Brave-Browser-Nightly"
  "$HOME/.config/microsoft-edge"
  "$HOME/.config/microsoft-edge-beta"
  "$HOME/.config/microsoft-edge-dev"
  "$HOME/.config/vivaldi"
  "$HOME/.config/opera"
  "$HOME/.config/helium"
)

find_pending() {
  pending=()
  for profile_root in "${profile_roots[@]}"; do
    [[ -d $profile_root ]] || continue

    for preferences in "$profile_root"/*/Preferences; do
      [[ -f $preferences ]] || continue
      python3 -c "$repair_py" "$preferences" "$pinned_id" "$accelerator" "$suggested_key" "$backup_suffix" check || continue
      pending+=("$preferences")
    done
  done
}

unverified_repairs_exist() {
  local profile_root backup

  for profile_root in "${profile_roots[@]}"; do
    for backup in "$profile_root"/*/"Preferences${backup_suffix}"; do
      [[ -f $backup ]] && return 0
    done
  done

  return 1
}

profile_open() {
  [[ -L $1/SingletonLock || -e $1/SingletonLock || -S $1/SingletonSocket ]]
}

affected_profile_open() {
  local preferences profile_root backup

  for preferences in "${pending[@]-}"; do
    [[ -n $preferences ]] || continue
    profile_open "$(dirname "$(dirname "$preferences")")" && return 0
  done

  for profile_root in "${profile_roots[@]}"; do
    for backup in "$profile_root"/*/"Preferences${backup_suffix}"; do
      [[ -f $backup ]] || continue
      profile_open "$(dirname "$(dirname "$backup")")" && return 0
    done
  done

  return 1
}

find_pending
if (( ! ${#pending[@]} )) && ! unverified_repairs_exist; then
  exit 0
fi

while affected_profile_open; do
  if ! gum confirm "Close the browser windows to enable Subscribe to Feeds, then continue"; then
    echo "A running browser would undo the Subscribe to Feeds shortcut." >&2
    echo "Close the browser windows, then run: omarchy-migrate" >&2
    exit 1
  fi
done

find_pending

for preferences in "${pending[@]-}"; do
  [[ -n $preferences ]] || continue
  python3 -c "$repair_py" "$preferences" "$pinned_id" "$accelerator" "$suggested_key" "$backup_suffix" repair
done

if affected_profile_open; then
  echo "A browser started during the Subscribe to Feeds shortcut repair." >&2
  echo "Close the browser windows, then run: omarchy-migrate" >&2
  exit 1
fi

for preferences in "${pending[@]-}"; do
  [[ -n $preferences ]] || continue
  if python3 -c "$repair_py" "$preferences" "$pinned_id" "$accelerator" "$suggested_key" "$backup_suffix" check; then
    echo "A browser undid the Subscribe to Feeds shortcut repair on exit." >&2
    echo "Close the browser windows, then run: omarchy-migrate" >&2
    exit 1
  fi
done
