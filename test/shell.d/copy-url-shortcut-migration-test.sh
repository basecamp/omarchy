#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command python3

migration="$ROOT/migrations/1786643346.sh"
test_dir=$(mktemp -d)

# A live browser process to name in the locks; its pid stays allocated for the
# whole run, and a socket target that stays resolvable.
sleep 600 & live_browser_pid=$!
live_socket_file="$test_dir/live-singleton-socket"
: >"$live_socket_file"
trap 'rm -rf "$test_dir"; kill "$live_browser_pid" 2>/dev/null || true' EXIT

home="$test_dir/home"
profile_root="$home/.config/chromium"
preferences="$profile_root/Default/Preferences"
mkdir -p "$(dirname "$preferences")"

# Any id Chromium once derived from the extension's keyless load path; the
# repair keys off the registered command name, not the id.
ghost_id="ikkebdkaanlebnifjnbeiaklodhbjcci"
pinned_id="bgpiichlckmfanooecilcjemknkcpngb"

write_stale_preferences() {
  jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {($ghost): {commands: {"copy-url": {suggested_key: "Alt+Shift+L", was_assigned: true}}}, ($pinned): {commands: {"copy-url": {suggested_key: "Alt+Shift+L"}}}}}}' >"$preferences"
}

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

REAL_PYTHON=$(command -v python3)
export REAL_PYTHON

run_migration() {
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1
}

# A running Chromium-family browser marks its profile root with a SingletonLock
# symlink to <hostname>-<pid> of a live browser process, and SingletonSocket
# pointing at a socket that still exists. That pair — not the mere presence of
# a browser process — is what the migration waits on.
create_browser_lock() {
  ln -sfn "$(uname -n)-$live_browser_pid" "$1/SingletonLock"
  ln -sfn "$live_socket_file" "$1/SingletonSocket"
}
open_browser() {
  mkdir -p "$profile_root"
  create_browser_lock "$profile_root"
}
close_browser() {
  rm -f "$profile_root/SingletonLock" "$profile_root/SingletonSocket"
}

# The affected profile being open prompts for the windows to be closed;
# declining (or having no terminal to ask in) defers the repair so a
# rewrite-on-exit cannot revert it.
printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
chmod +x "$stub_bin/gum"
write_stale_preferences
open_browser

before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)

run_migration && fail "migration defers while the affected profile is open"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves preferences alone while the affected profile is open"
pass "migration defers the repair while the affected profile is open"

# A crash or reboot leaves both Singleton symlinks behind as dangling links:
# the pid named in the lock belongs to the dead session, and the socket under
# /tmp is gone with it. Chromium itself reclaims such a lock on its next
# start, so the migration must not wait on it — otherwise the close-the-browser
# prompt loops forever no matter how often it is answered (#6866). gum still
# declines here: a migration that wrongly prompts fails rather than hangs.
sleep 600 & dead_session_pid=$!
kill "$dead_session_pid" 2>/dev/null || true
wait "$dead_session_pid" 2>/dev/null || true

write_stale_preferences
ln -sfn "$(uname -n)-$dead_session_pid" "$profile_root/SingletonLock"
ln -sfn "$test_dir/socket-gone-with-tmp" "$profile_root/SingletonSocket"
run_migration || fail "migration repairs past a stale lock left by a dead session"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs the shortcut under a stale singleton lock"
pass "migration ignores a stale lock whose pid died with the session"
rm -f "$preferences.omarchy-copy-url-repair.bak" "$profile_root/SingletonLock" "$profile_root/SingletonSocket"

# A pid from a dead session can be reused by an unrelated process, so a live
# pid alone must not read as an attached browser: the socket dies with the
# browser, and a dangling socket means nothing is holding the lock.
write_stale_preferences
ln -sfn "$(uname -n)-$live_browser_pid" "$profile_root/SingletonLock"
ln -sfn "$test_dir/socket-gone-with-tmp" "$profile_root/SingletonSocket"
run_migration || fail "migration repairs past a recycled pid with a dangling socket"
pass "migration ignores a lock held by a recycled pid and a dead socket"
rm -f "$preferences.omarchy-copy-url-repair.bak" "$profile_root/SingletonLock" "$profile_root/SingletonSocket"

# A lock naming another host is a leftover from before a hostname change or a
# copied profile; the browser it names cannot be running on this machine.
write_stale_preferences
ln -sfn "some-other-host-$live_browser_pid" "$profile_root/SingletonLock"
ln -sfn "$live_socket_file" "$profile_root/SingletonSocket"
run_migration || fail "migration repairs past a lock naming another host"
pass "migration ignores a lock naming another host"
rm -f "$preferences.omarchy-copy-url-repair.bak" "$profile_root/SingletonLock" "$profile_root/SingletonSocket"

# A browser that crashed without a reboot leaves its socket file behind under
# /tmp until the next reboot, so a resolvable socket alone cannot mean
# attached either: the pid it served is gone, and no browser holds the lock.
write_stale_preferences
ln -sfn "$(uname -n)-$dead_session_pid" "$profile_root/SingletonLock"
ln -sfn "$live_socket_file" "$profile_root/SingletonSocket"
run_migration || fail "migration repairs past a crashed browser's lingering socket"
pass "migration ignores a crashed browser's lingering socket"
rm -f "$preferences.omarchy-copy-url-repair.bak" "$profile_root/SingletonLock" "$profile_root/SingletonSocket"

# gum paints its prompt on stderr, so that stream has to stay attached:
# suppressing it leaves gum reading keys behind an unpainted screen, which
# reads as a hung update.
write_stale_preferences
open_browser
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
echo "gum-prompt-painted" >&2
exit 1
STUB
prompt_stderr="$test_dir/prompt-stderr"
HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>"$prompt_stderr" &&
  fail "migration defers when the browser prompt is declined"
grep -q "gum-prompt-painted" "$prompt_stderr" || fail "migration keeps the browser prompt visible"
pass "migration keeps the browser prompt visible"

# A browser holding a different profile root cannot revert this repair, so it
# must not hold the update: the repair goes through without ever reaching the
# prompt, which the still-declining gum stub would otherwise fail.
close_browser
mkdir -p "$home/.config/google-chrome"
create_browser_lock "$home/.config/google-chrome"
write_stale_preferences
run_migration || fail "migration repairs while a different profile root is open"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs the shortcut while a different profile root is open"
pass "migration ignores a browser on a different profile root"
rm -f "$home/.config/google-chrome/SingletonLock" "$home/.config/google-chrome/SingletonSocket" "$preferences.omarchy-copy-url-repair.bak"

# Closing the affected profile and confirming the prompt lets the repair
# proceed.
write_stale_preferences
open_browser
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
"$CLOSE_BROWSER"
touch "${GUM_CALLED:?}"
exit 0
STUB
cat >"$stub_bin/close-browser" <<'STUB'
#!/bin/bash
rm -f "$HOME/.config/chromium/SingletonLock"
STUB
chmod +x "$stub_bin/gum" "$stub_bin/close-browser"
GUM_CALLED="$test_dir/gum-called" CLOSE_BROWSER="$stub_bin/close-browser" \
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "migration proceeds once the profile is closed and the prompt confirmed"
[[ -e $test_dir/gum-called ]] || fail "migration asks before repairing under a running browser"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration repairs after the browser prompt is confirmed"
pass "migration asks to close the browser and repairs on confirmation"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# With the affected profile closed the ghost registration moves to the pinned id.
printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
close_browser
write_stale_preferences
run_migration || fail "migration repairs the shortcut when no browser is running"

jq -e --arg ghost "$ghost_id" --arg pinned "$pinned_id" '
  .extensions.commands["linux:Alt+Shift+L"].extension == $pinned and
  (.extensions.settings | has($ghost) | not) and
  .extensions.settings[$pinned].commands["copy-url"].was_assigned == true
' "$preferences" >/dev/null || fail "migration rebinds the Copy URL shortcut to the pinned extension id"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration backs up preferences before the repair"
pass "migration rebinds the Copy URL shortcut to the pinned extension id"

# A repaired profile has no ghost registration left, so nothing is pending —
# even while that same profile is open.
rm "$preferences.omarchy-copy-url-repair.bak"
repaired_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
open_browser
run_migration || fail "migration reruns cleanly after the repair"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$repaired_hash" && ! -e $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration is idempotent after the repair"
pass "migration is idempotent after the repair"
close_browser

# A remapped shortcut keeps the user's chosen key while moving to the pinned id.
jq -n --arg ghost "$ghost_id" '{extensions: {commands: {"linux:Ctrl+Alt+P": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {}}}' >"$preferences"
run_migration || fail "migration repairs remapped shortcuts"
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Ctrl+Alt+P"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration keeps the remapped key while rebinding to the pinned id"
pass "migration keeps remapped shortcut keys"

# When the pinned extension already holds a copy-url binding (the user fixed
# it by hand), the ghost is dropped rather than doubled into a second binding.
jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Ctrl+Alt+P": {command_name: "copy-url", extension: $pinned, global: false}, "linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}}, settings: {}}}' >"$preferences"
run_migration || fail "migration cleans ghosts alongside a manual repair"
jq -e --arg pinned "$pinned_id" '
  (.extensions.commands | has("linux:Alt+Shift+L") | not) and
  .extensions.commands["linux:Ctrl+Alt+P"].extension == $pinned
' "$preferences" >/dev/null || fail "migration drops the ghost instead of double-binding the pinned extension"
pass "migration never double-binds the pinned extension"

# A browser starting mid-repair may write stale Preferences back on exit, so
# the migration must stay pending for a later browser-free run to verify. A
# stub hands the repair call through and opens the profile right after it.
write_stale_preferences
close_browser
rm -f "$preferences.omarchy-copy-url-repair.bak"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
# Called as `python3 -c <script> <preferences> <pinned_id> <check|repair>`, and
# the check calls report a surviving ghost through their exit status.
"${REAL_PYTHON}" "$@"
status=$?
[[ ${5:-} == "repair" ]] && {
  ln -sfn "$LIVE_LOCK_TARGET" "$HOME/.config/chromium/SingletonLock"
  ln -sfn "$LIVE_SOCKET_TARGET" "$HOME/.config/chromium/SingletonSocket"
}
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$PATH" LIVE_LOCK_TARGET="$(uname -n)-$live_browser_pid" \
  LIVE_SOCKET_TARGET="$live_socket_file" bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration stays pending when a browser starts mid-repair"
fi
jq -e --arg pinned "$pinned_id" '.extensions.commands["linux:Alt+Shift+L"].extension == $pinned' "$preferences" >/dev/null ||
  fail "migration still repairs preferences before deferring on a late browser"
pass "migration stays pending when a browser starts mid-repair"
rm -f "$stub_bin/python3" "$preferences.omarchy-copy-url-repair.bak"
close_browser

# A browser that started and exited mid-repair restores stale Preferences
# before the final profile check; the post-repair file verification catches it.
write_stale_preferences
cp "$preferences" "$test_dir/stale-preferences"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
"${REAL_PYTHON}" "$@"
status=$?
[[ ${5:-} == "repair" ]] && cp "${STALE_PREFERENCES:?}" "${REPAIRED_PREFERENCES:?}"
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$PATH" STALE_PREFERENCES="$test_dir/stale-preferences" \
  REPAIRED_PREFERENCES="$preferences" bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration stays pending when a briefly-lived browser undoes the repair"
fi
pass "migration stays pending when a briefly-lived browser undoes the repair"
rm -f "$stub_bin/python3"
close_browser
write_stale_preferences
run_migration || fail "migration recovers after a reverted repair"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# A repair attempted while the affected profile was open leaves its backup
# behind. A rerun that sees a clean disk while that profile still runs must
# stay pending — the browser can restore the ghost on exit — and only a
# browser-free rerun verifies the repair and completes.
write_stale_preferences
run_migration || fail "repair run before the verification scenario"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] || fail "verification scenario has a repair backup"
open_browser
run_migration && fail "migration must not complete an unverified repair while a browser runs"
pass "migration keeps an unverified repair pending while a browser runs"
close_browser
run_migration || fail "migration completes once the repair is verified with browsers closed"
pass "migration verifies an attempted repair on a browser-free rerun"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# An installed third-party extension with a command that happens to be named
# copy-url keeps its own registration.
jq -n '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", global: false}}, settings: {aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: {path: "/home/user/.config/some-extension", commands: {}}}}}' >"$preferences"
untouched_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration leaves installed third-party extensions alone"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$untouched_hash" ]] ||
  fail "migration does not steal a third-party copy-url command registration"
pass "migration leaves installed third-party extensions alone"
