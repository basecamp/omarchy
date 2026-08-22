echo "Repair the Copy URL shortcut for profiles that predate its pinned extension id"

# Chromium never hands a suggested shortcut to one extension while another —
# even a long-gone one — still holds the registration. Profiles that first
# loaded Copy URL before its id was pinned registered Alt+Shift+L under an id
# derived from the extension's load path at the time, so the pinned extension
# never receives the shortcut and the keypress does nothing. Those historical
# ids are unknowable in general (they hash long-gone absolute paths), but the
# registration itself names the command: rebind any copy-url command that
# points away from the pinned id, unless that id belongs to an extension that
# is actually installed.

pinned_id="bgpiichlckmfanooecilcjemknkcpngb"

repair_py=$(cat <<'PY'
import json
import shutil
import sys
from pathlib import Path

path = Path(sys.argv[1])
pinned_id = sys.argv[2]
mode = sys.argv[3]

try:
    preferences = json.loads(path.read_text())
except (OSError, ValueError):
    sys.exit(1)

extensions = preferences.get("extensions", {})
commands = extensions.get("commands", {})
settings = extensions.get("settings", {})

def ghost_id(command):
    if command.get("command_name") != "copy-url":
        return None
    extension = command.get("extension")
    if not extension or extension == pinned_id:
        return None
    # An installed extension records its install path in settings; only the
    # ghosts of Copy URL itself may be rebound.
    install_path = settings.get(extension, {}).get("path", "")
    if install_path and not install_path.endswith("/default/chromium/extensions/copy-url"):
        return None
    return extension

if mode == "check":
    sys.exit(0 if any(ghost_id(c) for c in commands.values()) else 1)

# Chromium keeps one shortcut per command, so a ghost may only be rebound
# when the pinned extension holds no copy-url binding of its own; further
# ghosts are dropped rather than doubled up.
pinned_bound = any(
    c.get("command_name") == "copy-url" and c.get("extension") == pinned_id
    for c in commands.values()
)

changed = False
for accelerator in list(commands):
    ghost = ghost_id(commands[accelerator])
    if not ghost:
        continue
    if pinned_bound:
        del commands[accelerator]
    else:
        commands[accelerator]["extension"] = pinned_id
        pinned_bound = True
        pinned_command = settings.get(pinned_id, {}).get("commands", {}).get("copy-url", {})
        if pinned_command:
            pinned_command["was_assigned"] = True
    settings.pop(ghost, None)
    changed = True

if changed:
    shutil.copy2(path, path.with_name(path.name + ".omarchy-copy-url-repair.bak"))
    path.write_text(json.dumps(preferences, separators=(",", ":")))
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
      python3 -c "$repair_py" "$preferences" "$pinned_id" check || continue
      pending+=("$preferences")
    done
  done
}

# The backup a repair leaves next to Preferences marks it as attempted but not
# yet verified: a browser that was open during the repair still holds the
# stale registration in memory and restores it when it exits, possibly after
# the disk was already seen clean.
unverified_repairs_exist() {
  local profile_root backup

  for profile_root in "${profile_roots[@]}"; do
    for backup in "$profile_root"/*/Preferences.omarchy-copy-url-repair.bak; do
      [[ -f $backup ]] && return 0
    done
  done

  return 1
}

# A browser only rewrites its own Preferences on exit, so a repair can only be
# reverted by a browser attached to a profile this migration has to touch.
# Whether a profile is open is mechanical: a running Chromium-family browser
# holds a SingletonLock (and socket) inside its user-data-dir.
profile_open() {
  # -L catches a SingletonLock left as a dangling symlink; -e covers a plain
  # file, and -S the socket — any of them means a browser is attached.
  [[ -L $1/SingletonLock || -e $1/SingletonLock || -S $1/SingletonSocket ]]
}

# Gate on a pending — or to-be-verified — profile actually being open, not on
# browsers in general. Waiting on every browser process deadlocks the update on
# machines whose main browser is effectively never closed: the pending ghosts
# commonly sit in a stale profile nobody has open, yet the update blocks on the
# always-open one.
affected_profile_open() {
  local preferences backup profile_root

  for preferences in "${pending[@]}"; do
    profile_open "$(dirname "$(dirname "$preferences")")" && return 0
  done

  for profile_root in "${profile_roots[@]}"; do
    for backup in "$profile_root"/*/Preferences.omarchy-copy-url-repair.bak; do
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

# A running browser holds Preferences in memory and rewrites the file on exit,
# reverting the repair, so ask for the affected windows to be closed first. gum
# draws the prompt on stderr, so it must stay attached: suppressing it leaves
# gum waiting for a keypress behind an unpainted screen. Without a terminal to
# ask in, gum fails; then — as on decline — fail so the migration stays
# pending, and the login notifier keeps prompting until a rerun goes through
# with the affected profiles closed.
while affected_profile_open; do
  if ! gum confirm "Close the browser windows to repair the Copy URL shortcut, then continue"; then
    echo "A running browser would undo the Copy URL shortcut repair." >&2
    echo "Close the browser windows, then run: omarchy-migrate" >&2
    exit 1
  fi
done

# A browser that just closed may have restored ghosts an earlier repair had
# already removed, so only now is the pending list authoritative.
find_pending

for preferences in "${pending[@]}"; do
  python3 -c "$repair_py" "$preferences" "$pinned_id" repair
done

# A browser that started mid-repair read the stale Preferences and will write
# them back on exit; stay pending so the next browser-free run can verify the
# repair stuck.
if affected_profile_open; then
  echo "A browser started during the Copy URL shortcut repair and may undo it on exit." >&2
  echo "Close the browser windows, then run: omarchy-migrate" >&2
  exit 1
fi

# One that started and already exited mid-repair wrote its stale in-memory
# Preferences back over the repair; verify every file again. A browser
# starting after this point reads the repaired file, so it can no longer
# restore the ghost.
for preferences in "${pending[@]}"; do
  if python3 -c "$repair_py" "$preferences" "$pinned_id" check; then
    echo "A browser undid the Copy URL shortcut repair on exit." >&2
    echo "Close the browser windows, then run: omarchy-migrate" >&2
    exit 1
  fi
done
