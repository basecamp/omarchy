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

# --- PKGBUILD-style Arch dependencies ---------------------------------------
#
# The installer reads 'dependencies' to offer missing packages for install.
# Required ones are plain name arrays split by source; optional ones use the
# PKGBUILD "name: reason" optdepends strings. Validation keeps malformed
# declarations out before anything is offered to the user.
dir=$(write_plugin "deps-ok" '["bar-widget"]' '{"barWidget": "Widget.qml"}')
jq '. + {
  "dependencies": {
    "pacman": ["jq", "gum"],
    "aur": ["some-aur-package"],
    "optdepends": {
      "pacman": ["brightnessctl: needed for the brightness slider"],
      "aur": ["google-chrome: needed for the browser widget"]
    }
  }
}' "$dir/manifest.json" >"$dir/manifest.tmp" && mv "$dir/manifest.tmp" "$dir/manifest.json"
validate "$dir" >/dev/null || fail "validate accepts a well-formed dependencies block"
pass "validate accepts a well-formed dependencies block"

dir=$(write_plugin "deps-not-object" '["bar-widget"]' '{"barWidget": "Widget.qml"}')
jq '. + {"dependencies": ["jq"]}' "$dir/manifest.json" >"$dir/manifest.tmp" \
  && mv "$dir/manifest.tmp" "$dir/manifest.json"
output=$(validate "$dir") && fail "validate refuses a non-object dependencies block" "$output"
grep -qF "'dependencies' must be an object" <<<"$output" \
  || fail "validate explains the dependencies object contract" "$output"
pass "validate refuses a non-object dependencies block"

dir=$(write_plugin "deps-bad-pacman" '["bar-widget"]' '{"barWidget": "Widget.qml"}')
jq '. + {"dependencies": {"pacman": "jq"}}' "$dir/manifest.json" >"$dir/manifest.tmp" \
  && mv "$dir/manifest.tmp" "$dir/manifest.json"
output=$(validate "$dir") && fail "validate refuses a non-array pacman dependency list" "$output"
grep -qF "'dependencies.pacman' must be an array of package names" <<<"$output" \
  || fail "validate explains the pacman dependency array contract" "$output"
pass "validate refuses a non-array pacman dependency list"

dir=$(write_plugin "deps-bad-optdep" '["bar-widget"]' '{"barWidget": "Widget.qml"}')
jq '. + {"dependencies": {"optdepends": {"pacman": ["brightnessctl no reason here"]}}}' \
  "$dir/manifest.json" >"$dir/manifest.tmp" && mv "$dir/manifest.tmp" "$dir/manifest.json"
output=$(validate "$dir") && fail "validate refuses an optdepends entry without a reason" "$output"
grep -qF "'dependencies.optdepends.pacman' entries must be 'name: reason' strings" <<<"$output" \
  || fail "validate explains the optdepends string contract" "$output"
pass "validate refuses an optdepends entry without a reason"

dir=$(write_plugin "deps-bad-optdep-shape" '["bar-widget"]' '{"barWidget": "Widget.qml"}')
jq '. + {"dependencies": {"optdepends": "brightnessctl: x"}}' \
  "$dir/manifest.json" >"$dir/manifest.tmp" && mv "$dir/manifest.tmp" "$dir/manifest.json"
output=$(validate "$dir") && fail "validate refuses a non-object optdepends block" "$output"
grep -qF "'dependencies.optdepends' must be an object with pacman/aur arrays" <<<"$output" \
  || fail "validate explains the optdepends object contract" "$output"
pass "validate refuses a non-object optdepends block"
