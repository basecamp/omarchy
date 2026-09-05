#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command python3

migration="$ROOT/migrations/1786643346.sh"
retry_migration=$(grep -l 'Retry the Copy URL shortcut repair after install-time migration stamping' "$ROOT/migrations"/*.sh | head -n 1 || true)
repair_cmd="$ROOT/bin/omarchy-cmd-repair-chromium-copy-url"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
profile_root="$home/.config/chromium"
preferences="$profile_root/Default/Preferences"
mkdir -p "$(dirname "$preferences")"

# Any id Chromium once derived from the extension's keyless load path; the
# repair keys off the registered command name, not the id.
ghost_id="ikkebdkaanlebnifjnbeiaklodhbjcci"
pinned_id="bgpiichlckmfanooecilcjemknkcpngb"

write_stale_preferences() {
  jq -n --arg ghost "$ghost_id" --arg pinned "$pinned_id" '{
    extensions: {
      commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: $ghost, global: false}},
      settings: {
        ($ghost): {commands: {"copy-url": {suggested_key: "Alt+Shift+L", was_assigned: true}}},
        ($pinned): {commands: {"copy-url": {suggested_key: "Alt+Shift+L"}}}
      }
    },
    protection: {macs: {extensions: {commands: "stale-command-mac", settings: {($ghost): "stale-settings-mac"}}}}
  }' >"$preferences"
}

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
exit 127
STUB
chmod +x "$stub_bin/python3"

# Test stubs must delegate to the system interpreter, not a user shim that can
# route python3 back through the stubs and recurse.
REAL_PYTHON=$(PATH="$stub_bin:$PATH" command -p -v python3)
[[ $REAL_PYTHON != "$stub_bin/python3" ]] || fail "real Python resolution bypasses user shims"
export REAL_PYTHON
rm -f "$stub_bin/python3"

run_repair() {
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" "$repair_cmd" >/dev/null 2>&1
}

run_migration() {
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1
}

# A running Chromium-family browser marks its profile root with a SingletonLock
# symlink to <hostname>-<pid>. Only a live PID counts as attached; a lock left
# by SIGTERM still points at a dead pid and must not block the repair.
open_browser() {
  mkdir -p "$profile_root"
  ln -sfn "test-host-$$" "$profile_root/SingletonLock"
}
stale_browser_lock() {
  mkdir -p "$profile_root"
  ln -sfn "test-host-999999999" "$profile_root/SingletonLock"
}
close_browser() {
  rm -f "$profile_root/SingletonLock"
}

assert_repaired() {
  jq -e --arg ghost "$ghost_id" --arg pinned "$pinned_id" '
    .extensions.commands["linux:Alt+Shift+L"].extension == $pinned and
    (.extensions.settings | has($ghost) | not) and
    .extensions.settings[$pinned].commands["copy-url"].was_assigned == true and
    (has("protection") | not)
  ' "$preferences" >/dev/null
}

assert_no_tmp() {
  local leftover
  leftover=$(find "$profile_root/Default" -maxdepth 1 \( -name '.Preferences.*' -o -name 'Preferences.tmp*' \))
  [[ -z $leftover ]]
}

grep -F 'omarchy-cmd-repair-chromium-copy-url --prompt' "$migration" >/dev/null ||
  fail "1786643346 delegates to the shared repair command"
[[ -n $retry_migration && -f $retry_migration ]] ||
  fail "a follow-up migration retries the repair for already-stamped installs"
grep -F 'omarchy-cmd-repair-chromium-copy-url --prompt' "$retry_migration" >/dev/null ||
  fail "follow-up migration delegates to the shared repair command"
pass "migrations keep the repair for unstamped upgrades and already-stamped installs"

grep -F 'first-run/chromium-copy-url.sh' "$ROOT/bin/omarchy-provision-first-run" >/dev/null ||
  fail "first-run does not invoke the Copy URL repair"
grep -F 'omarchy-cmd-repair-chromium-copy-url' "$ROOT/bin/omarchy-migrate-notify" >/dev/null ||
  fail "login notifier does not retry the Copy URL repair"
grep -F 'omarchy-cmd-repair-chromium-copy-url' "$ROOT/bin/omarchy-launch-browser" >/dev/null ||
  fail "browser launch does not retry the Copy URL repair"
grep -F 'omarchy-cmd-repair-chromium-copy-url' "$ROOT/bin/omarchy-launch-webapp" >/dev/null ||
  fail "web app launch does not retry the Copy URL repair"
pass "Copy URL repair is invoked from non-stamped first-run, login, and launch hooks"

# A running Chromium-family browser marks its profile root with a SingletonLock
# symlink to <hostname>-<pid>, a target that never exists on disk. That lock —
# not the mere presence of a browser process — is what the repair waits on.
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

# Quiet callers skip without gum and without failing — login and browser launch
# must not block on a running profile.
run_repair || fail "quiet repair skips while the affected profile is open"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "quiet repair leaves preferences alone while the affected profile is open"
pass "quiet repair skips while the affected profile is open"

# A dangling SingletonLock whose pid is dead is not an attached browser; SIGTERM
# leaves that symlink behind and the repair must still persist.
stale_browser_lock
run_repair || fail "quiet repair proceeds past a stale SingletonLock"
assert_repaired || fail "quiet repair rewrites preferences behind a stale lock"
assert_no_tmp || fail "repair leaves no Preferences temp file behind a stale lock"
pass "stale SingletonLock does not block the repair"
rm -f "$preferences.omarchy-copy-url-repair.bak"
close_browser

# gum paints its prompt on stderr, so that stream has to stay attached:
# suppressing it leaves gum reading keys behind an unpainted screen, which
# reads as a hung update.
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
echo "gum-prompt-painted" >&2
exit 1
STUB
write_stale_preferences
open_browser
prompt_stderr="$test_dir/prompt-stderr"
HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>"$prompt_stderr" &&
  fail "migration defers when the browser prompt is declined"
grep -q "gum-prompt-painted" "$prompt_stderr" || fail "migration keeps the browser prompt visible"
pass "migration keeps the browser prompt visible"

# A browser holding a different profile root cannot revert this repair, so it
# must not hold the update: the repair goes through without ever reaching the
# prompt, which the still-declining gum stub would otherwise fail.
close_browser
mkdir -p "$home/.config/google-chrome"
ln -sfn "test-host-$$" "$home/.config/google-chrome/SingletonLock"
write_stale_preferences
run_migration || fail "migration repairs while a different profile root is open"
assert_repaired || fail "migration repairs the shortcut while a different profile root is open"
pass "migration ignores a browser on a different profile root"
rm -f "$home/.config/google-chrome/SingletonLock" "$preferences.omarchy-copy-url-repair.bak"

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
  HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "migration proceeds once the profile is closed and the prompt confirmed"
[[ -e $test_dir/gum-called ]] || fail "migration asks before repairing under a running browser"
assert_repaired || fail "migration repairs after the browser prompt is confirmed"
pass "migration asks to close the browser and repairs on confirmation"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# With the affected profile closed the ghost registration moves to the pinned id.
printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
close_browser
write_stale_preferences
run_migration || fail "migration repairs the shortcut when no browser is running"

assert_repaired || fail "migration rebinds the Copy URL shortcut to the pinned extension id"
[[ -f $preferences.omarchy-copy-url-repair.bak ]] ||
  fail "migration backs up preferences before the repair"
assert_no_tmp || fail "repair leaves no Preferences temp file after a successful write"
pass "migration rebinds the Copy URL shortcut to the pinned extension id"

# Install-time stamping must not prevent the command from repairing a profile
# that arrived later.
mkdir -p "$home/.local/state/omarchy/migrations"
touch "$home/.local/state/omarchy/migrations/1786643346.sh"
touch "$home/.local/state/omarchy/migrations/$(basename "$retry_migration")"
rm -f "$preferences.omarchy-copy-url-repair.bak"
write_stale_preferences
run_repair || fail "repair command runs even when the migrations are stamped complete"
assert_repaired || fail "stamped migrations still leave the command able to repair"
pass "repair command is independent of install-time migration stamps"
rm -f "$preferences.omarchy-copy-url-repair.bak"
rm -rf "$home/.local/state/omarchy/migrations"

# A repaired profile has no ghost registration left, so nothing is pending —
# even while that same profile is open.
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
[[ ${5:-} == "repair" ]] && ln -sfn "test-host-${LIVE_PID:?}" "$HOME/.config/chromium/SingletonLock"
exit $status
STUB
chmod +x "$stub_bin/python3"
if HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" LIVE_PID=$$ bash -euo pipefail "$migration" >/dev/null 2>&1; then
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
if HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" STALE_PREFERENCES="$test_dir/stale-preferences" \
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

# First-run invokes the quiet command, so a profile already present at first
# login is repaired without going through omarchy-migrate.
write_stale_preferences
HOME="$home" PATH="$stub_bin:$ROOT/bin:$PATH" bash "$ROOT/install/user/first-run/chromium-copy-url.sh" ||
  fail "first-run Copy URL hook repairs a present profile"
assert_repaired || fail "first-run Copy URL hook rebinds the pinned extension id"
pass "first-run hook repairs Copy URL when Preferences already exists"
rm -f "$preferences.omarchy-copy-url-repair.bak"

# An installed third-party extension with a command that happens to be named
# copy-url keeps its own registration.
jq -n '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", global: false}}, settings: {aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: {path: "/home/user/.config/some-extension", commands: {}}}}}' >"$preferences"
untouched_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration leaves installed third-party extensions alone"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$untouched_hash" ]] ||
  fail "migration does not steal a third-party copy-url command registration"
pass "migration leaves installed third-party extensions alone"
