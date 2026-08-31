#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

# The picker reads the plugin list from omarchy-plugin-list and hands what it
# decided to a verb-specific command, so stubbing both ends shows which plugin
# a pick actually resolved to -- the thing a source-level check cannot see.
cat >"$STUB_DIR/omarchy-plugin-list" <<'STUB'
#!/bin/bash
cat "$FAKE_PLUGINS"
STUB

for command in omarchy-plugin-enable omarchy-plugin-disable; do
  cat >"$STUB_DIR/$command" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$FAKE_CALLS"
STUB
done

# Records the rows it was offered, then answers with the pick under test.
cat >"$STUB_DIR/omarchy-menu-select" <<'STUB'
#!/bin/bash
cat >"$FAKE_ROWS"
printf '%s\n' "$FAKE_PICK"
STUB

cat >"$STUB_DIR/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$FAKE_CALLS"
STUB

cat >"$STUB_DIR/omarchy-launch-floating-terminal-with-presentation" <<'STUB'
#!/bin/bash
printf 'terminal: %s\n' "$*" >>"$FAKE_CALLS"
STUB

chmod +x "$STUB_DIR"/*

# Runs the picker against a plugin list, answering its prompt with $2. Leaves
# the rows it offered in $ROWS and what it called in $CALLS.
pick() {
  local verb="$1" choice="$2"

  : >"$TMPDIR/calls"
  : >"$TMPDIR/rows"
  HOME="$TMPDIR/home" \
    PATH="$STUB_DIR:$PATH" \
    FAKE_PLUGINS="$TMPDIR/plugins.json" \
    FAKE_CALLS="$TMPDIR/calls" \
    FAKE_ROWS="$TMPDIR/rows" \
    FAKE_PICK="$choice" \
    "$ROOT/bin/omarchy-menu-plugin" "$verb" >/dev/null 2>&1

  ROWS=$(cat "$TMPDIR/rows")
  CALLS=$(cat "$TMPDIR/calls")
}

# Two plugins can declare the same display name. The id rides along as row
# subtext and comes back with the selection, so the pick resolves by id.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": true},
  {"id": "tester.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

pick enable "$(printf 'Clock\ttester.clock')"
[[ $ROWS == *"$(printf 'Clock\tomarchy.clock')"* && $ROWS == *"$(printf 'Clock\ttester.clock')"* ]] \
  || fail "picker offers the id as subtext on every row" "$ROWS"
pass "picker offers the id as subtext on every row"
[[ $CALLS == *"omarchy-plugin-enable tester.clock"* ]] \
  || fail "picker acts on the row that was picked, not the one that shares its name" "$CALLS"
pass "picker acts on the row that was picked, not the one that shares its name"

pick remove "$(printf 'Clock\ttester.clock')"
[[ $CALLS == *"omarchy-plugin-remove tester.clock"* ]] \
  || fail "picker removes the plugin whose row was picked" "$CALLS"
pass "picker removes the plugin whose row was picked"

cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.weather", "name": "Weather", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

pick enable "$(printf 'Weather\tacme.weather')"
[[ $CALLS == *"omarchy-plugin-enable acme.weather"* ]] \
  || fail "picker delegates plugin enablement to the plugin command" "$CALLS"
pass "picker delegates plugin enablement to the plugin command"

# Clone offers only first-party plugins that no installed clone points back at,
# then hands the pick to the clone command, which opens the result in $EDITOR.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": true, "active": false, "canDisable": true, "firstParty": true},
  {"id": "acme.weather", "name": "Weather", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

pick clone "$(printf 'Clock\tomarchy.clock')"
[[ $ROWS == *"Clock"* && $ROWS != *"Weather"* ]] ||
  fail "clone picker offers only built-in plugins" "$ROWS"
pass "clone picker offers built-in plugins"
[[ $CALLS == *"terminal: omarchy-plugin-clone omarchy.clock --edit"* ]] ||
  fail "clone picker delegates cloning and editing to the clone command" "$CALLS"
pass "clone picker clones and opens the personal plugin"

# Once a clone pointing back at the source is discovered, whatever it is named,
# the source no longer belongs in Clone.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": true, "active": false, "canDisable": true, "firstParty": true},
  {"id": "tester.clock", "name": "My Clock", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false, "clonedFrom": "omarchy.clock"}
]
JSON

pick clone ""
[[ $CALLS == *"notification: No plugin to clone"* ]] ||
  fail "clone picker offers an already cloned plugin" "$CALLS"
pass "clone picker omits plugins already cloned locally"

# The picker treats every plugin alike and leaves kind-specific behavior to the
# plugin command.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.fancy", "name": "Fancy", "kinds": ["bar", "bar-widget"], "enabled": false, "active": false, "canDisable": false, "firstParty": false}
]
JSON

pick enable "$(printf 'Fancy\tacme.fancy')"
[[ $CALLS == *"omarchy-plugin-enable acme.fancy"* && $CALLS != *"--section"* ]] \
  || fail "picker delegates kind-specific enablement" "$CALLS"
pass "picker delegates kind-specific enablement"

# A bar has no off, so it is never offered under disable -- including this one,
# which is a widget too.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.fancy", "name": "Fancy", "kinds": ["bar", "bar-widget"], "enabled": true, "active": true, "canDisable": false, "firstParty": false},
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": true, "active": false, "canDisable": true, "firstParty": true}
]
JSON

pick disable "$(printf 'Clock\tomarchy.clock')"
[[ $ROWS == *"Clock"* && $ROWS != *"Fancy"* ]] \
  || fail "picker keeps a bar out of disable" "$ROWS"
pass "picker keeps a bar out of disable"

# The bar in use is the row absent from enable; every other bar is one pick away.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.bar", "name": "Bar", "kinds": ["bar"], "enabled": false, "active": false, "canDisable": false, "firstParty": true},
  {"id": "tester.neon-bar", "name": "Neon Bar", "kinds": ["bar"], "enabled": true, "active": true, "canDisable": false, "firstParty": false}
]
JSON

pick enable "$(printf 'Bar\tomarchy.bar')"
[[ $ROWS == *"Bar"* && $ROWS != *"Neon Bar"* ]] \
  || fail "picker offers every bar except the one already running" "$ROWS"
pass "picker offers every bar except the one already running"
[[ $CALLS == *"omarchy-plugin-enable omarchy.bar"* ]] \
  || fail "picker returns to the built-in bar by enabling it" "$CALLS"
pass "picker returns to the built-in bar by enabling it"

# Nothing the verb can act on is said out loud, not opened as an empty list.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.bar", "name": "Bar", "kinds": ["bar"], "enabled": true, "active": true, "canDisable": false, "firstParty": true}
]
JSON

pick enable ""
[[ $CALLS == *"notification: No plugin to enable"* ]] \
  || fail "picker says when a verb has nothing to act on" "$CALLS"
pass "picker says when a verb has nothing to act on"
