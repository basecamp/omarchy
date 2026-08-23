#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# A plugin folder with whatever kinds and entry points the case needs. Every
# entry point named gets a file, so a rejection is about the manifest and not a
# missing QML file.
write_plugin() {
  local name="$1" kinds="$2" entry_points="$3" bar_widget="${4:-null}"
  local dir="$TMPDIR/$name"
  local entry

  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "acme.$name",
  "name": "Acme $name",
  "version": "1.0.0",
  "kinds": $kinds,
  "entryPoints": $entry_points,
  "barWidget": $bar_widget
}
JSON

  while IFS= read -r entry; do
    [[ -n $entry ]] || continue
    touch "$dir/$entry"
  done < <(jq -r '.[]' <<<"$entry_points")

  printf '%s\n' "$dir"
}

validate() {
  OMARCHY_PATH="$ROOT" "$ROOT/bin/omarchy-plugin-validate" "$1" 2>&1
}

set_menu_item() {
  local dir="$1" value="$2"
  jq --argjson value "$value" '.menuItem = $value' "$dir/manifest.json" >"$dir/manifest.next.json"
  mv "$dir/manifest.next.json" "$dir/manifest.json"
}

# Every kind the shell knows how to load names the entry point it loads from.
# Declaring the kind without it installs a plugin that does nothing at all.
while IFS=: read -r kind entry_point; do
  dir=$(write_plugin "wants-$kind" "[\"$kind\"]" "{\"$entry_point\": \"Entry.qml\"}")
  validate "$dir" >/dev/null || fail "validate accepts $kind with its $entry_point entry point"
  pass "validate accepts $kind with its $entry_point entry point"

  # Swap in an entry point the kind does not read, so the manifest is otherwise
  # complete and only the promised one is missing.
  other_key="service"
  [[ $entry_point == "service" ]] && other_key="panel"
  dir=$(write_plugin "missing-$kind" "[\"$kind\"]" "{\"$other_key\": \"Entry.qml\"}")
  output=$(validate "$dir") && fail "validate refuses $kind without its $entry_point entry point" "$output"
  grep -qF "kind '$kind' requires an 'entryPoints.$entry_point' to load" <<<"$output" \
    || fail "validate names the entry point $kind is missing" "$output"
  pass "validate refuses $kind without its $entry_point entry point"
done <<'KINDS'
bar:bar
bar-widget:barWidget
menu:menu
overlay:overlay
panel:panel
service:service
KINDS

# A plugin that is both a bar and a widget owes an entry point for each.
dir=$(write_plugin "both" '["bar","bar-widget"]' '{"bar": "Bar.qml", "barWidget": "Widget.qml"}')
validate "$dir" >/dev/null || fail "validate accepts a plugin that satisfies every kind it declares"
pass "validate accepts a plugin that satisfies every kind it declares"

dir=$(write_plugin "half" '["bar","bar-widget"]' '{"bar": "Bar.qml"}')
output=$(validate "$dir") && fail "validate refuses a plugin that satisfies only one of its kinds" "$output"
grep -qF "kind 'bar-widget' requires" <<<"$output" \
  || fail "validate names the unsatisfied kind" "$output"
pass "validate refuses a plugin that satisfies only one of its kinds"

# A widget can choose its default bar section, but no other section name.
for section in left center right; do
  dir=$(write_plugin "defaults-$section" '["bar-widget"]' '{"barWidget": "Widget.qml"}' "{\"defaultSection\": \"$section\"}")
  validate "$dir" >/dev/null || fail "validate accepts $section as a default bar widget section"
  pass "validate accepts $section as a default bar widget section"
done

dir=$(write_plugin "defaults-bottom" '["bar-widget"]' '{"barWidget": "Widget.qml"}' '{"defaultSection": "bottom"}')
output=$(validate "$dir") && fail "validate refuses an invalid default bar widget section" "$output"
grep -qF "'barWidget.defaultSection' must be left, center, or right" <<<"$output" \
  || fail "validate explains the default bar widget section contract" "$output"
pass "validate refuses an invalid default bar widget section"

# A menuItem is a presentation-only launcher for plugin kinds the shell can
# summon. Its fields are optional strings; the menu supplies the action.
dir=$(write_plugin "menu-item" '["overlay"]' '{"overlay": "Overlay.qml"}')
set_menu_item "$dir" '{}'
validate "$dir" >/dev/null || fail "validate accepts a menu launcher using manifest fallbacks"
pass "validate accepts a menu launcher using manifest fallbacks"

dir=$(write_plugin "menu-presentation" '["panel"]' '{"panel": "Panel.qml"}')
set_menu_item "$dir" '{"label":"Acme panel","icon":"P","iconFont":"icons","description":"Open Acme"}'
validate "$dir" >/dev/null || fail "validate accepts menu launcher presentation strings"
pass "validate accepts menu launcher presentation strings"

dir=$(write_plugin "menu-not-object" '["overlay"]' '{"overlay": "Overlay.qml"}')
set_menu_item "$dir" '"Acme"'
output=$(validate "$dir") && fail "validate refuses a non-object menu launcher" "$output"
grep -qF "'menuItem' must be an object" <<<"$output" \
  || fail "validate explains that menuItem must be an object" "$output"
pass "validate refuses a non-object menu launcher"

dir=$(write_plugin "menu-bad-field" '["overlay"]' '{"overlay": "Overlay.qml"}')
set_menu_item "$dir" '{"icon":42}'
output=$(validate "$dir") && fail "validate refuses non-string menu launcher presentation" "$output"
grep -qF "'menuItem' presentation fields must be strings" <<<"$output" \
  || fail "validate explains menu launcher presentation types" "$output"
pass "validate refuses non-string menu launcher presentation"

dir=$(write_plugin "menu-null-field" '["overlay"]' '{"overlay": "Overlay.qml"}')
set_menu_item "$dir" '{"description":null}'
output=$(validate "$dir") && fail "validate refuses null menu launcher presentation" "$output"
grep -qF "'menuItem' presentation fields must be strings" <<<"$output" \
  || fail "validate treats explicit null like every other non-string field" "$output"
pass "validate refuses null menu launcher presentation"

dir=$(write_plugin "menu-empty-label" '["overlay"]' '{"overlay": "Overlay.qml"}')
set_menu_item "$dir" '{"label":""}'
output=$(validate "$dir") && fail "validate refuses an empty menu launcher label" "$output"
grep -qF "'menuItem.label' must not be empty" <<<"$output" \
  || fail "validate explains an empty menu launcher label" "$output"
pass "validate refuses an empty menu launcher label"

dir=$(write_plugin "menu-service" '["service"]' '{"service": "Service.qml"}')
set_menu_item "$dir" '{}'
output=$(validate "$dir") && fail "validate refuses a launcher for a service-only plugin" "$output"
grep -qF "'menuItem' requires a summonable kind" <<<"$output" \
  || fail "validate explains which plugins can expose a menu launcher" "$output"
pass "validate refuses a launcher for a service-only plugin"

# A kind the table does not cover is left alone rather than guessed at, so an
# unknown kind is not turned into a demand for an entry point nobody reads.
dir=$(write_plugin "unknown" '["future-thing"]' '{"service": "Entry.qml"}')
validate "$dir" >/dev/null || fail "validate leaves a kind it does not know alone"
pass "validate leaves a kind it does not know alone"

# The check reports the manifest, so a path that does not resolve still gets the
# more specific complaint it had before.
dir="$TMPDIR/ghost"
mkdir -p "$dir"
cat >"$dir/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "id": "acme.ghost",
  "name": "Acme Ghost",
  "version": "1.0.0",
  "kinds": ["bar"],
  "entryPoints": { "bar": "Missing.qml" }
}
JSON
output=$(validate "$dir") && fail "validate refuses an entry point file that is not there" "$output"
grep -qF "entry point file not found" <<<"$output" \
  || fail "validate reports a missing file as a missing file" "$output"
pass "validate refuses an entry point file that is not there"
