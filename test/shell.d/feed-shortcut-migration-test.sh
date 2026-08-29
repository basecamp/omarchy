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
