#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command python3

migration="$ROOT/migrations/1788029095.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
profile_root="$home/.config/chromium"
preferences="$profile_root/Default/Preferences"
pinned_id="bgpiichlckmfanooecilcjemknkcpngb"
backup="$preferences.omarchy-feed-shortcut.bak"
stub_bin="$test_dir/bin"
mkdir -p "$(dirname "$preferences")" "$stub_bin"

REAL_PYTHON=$(PATH="$stub_bin:$PATH" command -p -v python3)
export REAL_PYTHON

write_existing_profile() {
  jq -n --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Alt+Shift+L": {command_name: "copy-url", extension: $pinned, global: false}}, settings: {($pinned): {commands: {"copy-url": {suggested_key: "Alt+Shift+L", was_assigned: true}}}}}}' >"$preferences"
}

run_migration() {
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1
}

open_browser() {
  ln -sfn "test-host-1234" "$profile_root/SingletonLock"
}

close_browser() {
  rm -f "$profile_root/SingletonLock"
}

printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
chmod +x "$stub_bin/gum"

# A closed existing profile receives the new command without disturbing Copy URL.
write_existing_profile
run_migration || fail "migration assigns the feed shortcut to an existing profile"
jq -e --arg pinned "$pinned_id" '
  .extensions.commands["linux:Alt+Shift+L"].command_name == "copy-url" and
  .extensions.commands["linux:Alt+Shift+F"].command_name == "subscribe-feed" and
  .extensions.commands["linux:Alt+Shift+F"].extension == $pinned and
  .extensions.settings[$pinned].commands["subscribe-feed"].suggested_key == "Alt+Shift+F" and
  .extensions.settings[$pinned].commands["subscribe-feed"].was_assigned == true
' "$preferences" >/dev/null || fail "migration writes Chromium's command and extension settings"
[[ -f $backup ]] || fail "migration backs up Preferences before assignment"
pass "migration assigns Subscribe to Feeds to existing profiles"

# A rerun preserves the assigned profile byte for byte.
rm -f "$backup"
assigned_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration reruns after assignment"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$assigned_hash" && ! -e $backup ]] ||
  fail "migration is idempotent after assignment"
pass "migration is idempotent after assignment"

# A user's remapped feed command remains untouched.
jq -n --arg pinned "$pinned_id" '{extensions: {commands: {"linux:Ctrl+Alt+F": {command_name: "subscribe-feed", extension: $pinned, global: false}}, settings: {($pinned): {commands: {"subscribe-feed": {suggested_key: "Ctrl+Alt+F", was_assigned: true}}}}}}' >"$preferences"
remapped_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration accepts a remapped feed command"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$remapped_hash" ]] ||
  fail "migration preserves a user's remapped feed shortcut"
pass "migration preserves remapped feed shortcuts"

# A shortcut owned by another extension is never stolen.
jq -n '{extensions: {commands: {"linux:Alt+Shift+F": {command_name: "other-action", extension: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", global: false}}, settings: {}}}' >"$preferences"
collision_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration skips a shortcut collision"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$collision_hash" ]] ||
  fail "migration leaves an occupied shortcut untouched"
pass "migration never steals an occupied shortcut"

# Chromium rewrites Preferences on exit, so an affected open profile defers.
write_existing_profile
open_browser
before_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration && fail "migration defers while the affected profile is open"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves an open profile unchanged"
pass "migration defers while the affected profile is open"
close_browser

# A browser attached to another profile cannot revert this Preferences file.
mkdir -p "$home/.config/google-chrome"
ln -sfn "test-host-1234" "$home/.config/google-chrome/SingletonLock"
write_existing_profile
run_migration || fail "migration proceeds while a different profile is open"
jq -e '.extensions.commands["linux:Alt+Shift+F"].command_name == "subscribe-feed"' "$preferences" >/dev/null ||
  fail "migration assigns the shortcut while an unrelated profile is open"
pass "migration ignores browsers on unrelated profiles"
rm -f "$home/.config/google-chrome/SingletonLock" "$backup"

# gum paints its prompt on stderr, so declining the browser-close request must
# leave that stream visible rather than looking like a hung update.
write_existing_profile
open_browser
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
echo "feed-shortcut-prompt-painted" >&2
exit 1
STUB
prompt_stderr="$test_dir/prompt-stderr"
if HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>"$prompt_stderr"; then
  fail "migration proceeds after the browser-close prompt is declined"
fi
grep -Fq 'feed-shortcut-prompt-painted' "$prompt_stderr" || fail "migration hides its browser-close prompt"
pass "migration keeps the browser-close prompt visible"

# Confirming after closing the affected browser allows the repair to proceed.
cat >"$stub_bin/gum" <<'STUB'
#!/bin/bash
rm -f "$HOME/.config/chromium/SingletonLock"
touch "${FEED_TEST_GUM_CALLED:?}"
exit 0
STUB
FEED_TEST_GUM_CALLED="$test_dir/gum-called" run_migration || fail "migration proceeds once the affected browser closes"
[[ -e $test_dir/gum-called ]] || fail "migration does not ask before repairing an open profile"
jq -e '.extensions.commands["linux:Alt+Shift+F"].command_name == "subscribe-feed"' "$preferences" >/dev/null ||
  fail "migration does not repair after the browser closes"
pass "migration repairs after explicit browser closure"
rm -f "$backup"

# A browser starting after the preflight check can still rewrite Preferences.
# The post-repair profile check must leave the migration pending.
write_existing_profile
close_browser
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
"$REAL_PYTHON" "$@"
status=$?
[[ ${8:-} == "repair" ]] && ln -sfn "test-host-1234" "$HOME/.config/chromium/SingletonLock"
exit $status
STUB
chmod +x "$stub_bin/python3"
if run_migration; then
  fail "migration completes when a browser starts during repair"
fi
jq -e '.extensions.commands["linux:Alt+Shift+F"].command_name == "subscribe-feed"' "$preferences" >/dev/null ||
  fail "late-browser detection loses the completed atomic profile repair"
[[ -f $backup ]] || fail "late-browser detection loses the recovery backup"
pass "migration stays pending when a browser starts during repair"
rm -f "$stub_bin/python3" "$backup"
close_browser

# A briefly-lived browser can restore stale Preferences before the final
# verification. The file-level check must detect that even without a lock.
write_existing_profile
cp -- "$preferences" "$test_dir/stale-preferences"
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
"$REAL_PYTHON" "$@"
status=$?
if [[ ${8:-} == "repair" ]]; then
  cp -- "${FEED_TEST_STALE_PREFERENCES:?}" "${FEED_TEST_PREFERENCES:?}"
fi
exit $status
STUB
chmod +x "$stub_bin/python3"
if FEED_TEST_STALE_PREFERENCES="$test_dir/stale-preferences" FEED_TEST_PREFERENCES="$preferences" run_migration; then
  fail "migration completes after a briefly-lived browser undoes the repair"
fi
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == $(sha256sum "$test_dir/stale-preferences" | cut -d' ' -f1) ]] ||
  fail "brief browser test does not reproduce the stale preference rewrite"
pass "migration detects a briefly-lived browser undoing the repair"
rm -f "$stub_bin/python3"
run_migration || fail "migration recovers from a browser-reverted repair"
rm -f "$backup"

# A previous repair backup means the result has not yet been verified with the
# browser closed. Do not complete that retry while the affected profile runs.
write_existing_profile
run_migration || fail "migration prepares the unverified-repair scenario"
[[ -f $backup ]] || fail "unverified-repair scenario has no recovery backup"
open_browser
if run_migration; then
  fail "migration verifies an earlier repair while the browser is open"
fi
close_browser
printf '#!/bin/bash\nexit 1\n' >"$stub_bin/gum"
chmod +x "$stub_bin/gum"
run_migration || fail "migration verifies an earlier repair once the browser closes"
pass "migration verifies attempted repairs only with the browser closed"
rm -f "$backup"

# Profiles are independent repair units. If the second profile fails, the
# first remains safely repaired and a later idempotent run completes the rest.
second_preferences="$home/.config/google-chrome/Profile 1/Preferences"
mkdir -p "$(dirname "$second_preferences")"
write_existing_profile
jq -n --arg pinned "$pinned_id" '{extensions: {commands: {}, settings: {($pinned): {commands: {}}}}}' >"$second_preferences"
second_before=$(sha256sum "$second_preferences" | cut -d' ' -f1)
cat >"$stub_bin/python3" <<'STUB'
#!/bin/bash
if [[ ${8:-} == "repair" && $3 == *"google-chrome/Profile 1/Preferences" ]]; then
  exit 74
fi
exec "$REAL_PYTHON" "$@"
STUB
chmod +x "$stub_bin/python3"
if run_migration; then
  fail "migration reports success after a later profile repair fails"
fi
jq -e '.extensions.commands["linux:Alt+Shift+F"].command_name == "subscribe-feed"' "$preferences" >/dev/null ||
  fail "a later profile failure corrupts the earlier completed profile"
[[ $(sha256sum "$second_preferences" | cut -d' ' -f1) == "$second_before" ]] ||
  fail "a failed profile repair changes that profile"
rm -f "$stub_bin/python3"
run_migration || fail "migration does not resume after a partial multi-profile run"
jq -e '.extensions.commands["linux:Alt+Shift+F"].command_name == "subscribe-feed"' "$second_preferences" >/dev/null ||
  fail "migration retry leaves the failed profile unrepaired"
pass "migration resumes safely after a later profile repair fails"

# Invalid browser state is not rewritten opportunistically.
printf '{not valid json\n' >"$preferences"
malformed_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
run_migration || fail "migration does not skip malformed browser preferences safely"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$malformed_hash" ]] || fail "migration rewrites malformed browser preferences"
pass "migration leaves malformed browser preferences untouched"
