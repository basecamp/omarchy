#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_plugin() {
  local dir="$1"
  local id="$2"
  local name="$3"
  local section="${4:-center}"

  mkdir -p "$dir"
  cat >"$dir/manifest.json" <<JSON
{
  "schemaVersion": 1,
  "id": "$id",
  "name": "$name",
  "version": "1.0.0",
  "kinds": ["bar-widget"],
  "entryPoints": { "barWidget": "Widget.qml" },
  "barWidget": {
    "displayName": "$name",
    "category": "Test",
    "allowMultiple": false,
    "defaultSection": "$section"
  }
}
JSON
  printf 'import QtQuick\nItem {}\n' >"$dir/Widget.qml"
}

commit_plugin() {
  git -C "$1" init -q
  git -C "$1" add .
  git -C "$1" -c user.name=Test -c user.email=test@example.com commit -qm "Initial"
}

stub_dir="$TMPDIR/stubs"
mkdir -p "$stub_dir"
cat >"$stub_dir/omarchy-shell" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_dir/omarchy-shell"

test_home="$TMPDIR/home"
write_plugin "$test_home/.config/omarchy/plugins/different-folder" "acme.same" "Installed"

incoming="$TMPDIR/incoming"
write_plugin "$incoming" "acme.same" "Incoming"
commit_plugin "$incoming"

output=$(HOME="$test_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  omarchy-plugin-add "$incoming" --yes 2>&1) &&
  fail "plugin add accepts an id already installed under another directory" "$output"
grep -qF "plugin id 'acme.same' is already used by" <<<"$output" ||
  fail "plugin add explains the installed id collision" "$output"
[[ ! -e $test_home/.config/omarchy/plugins/acme.same ]] ||
  fail "plugin add leaves a target behind after refusing a duplicate id"
pass "plugin add refuses an installed manifest id regardless of directory name"

# Enabling a bar widget is a config edit, so --enable must not depend on the
# shell having rescanned, or on a shell running at all. The stub answers every
# IPC call with silence, which is what a stopped shell looks like.
enable_home="$TMPDIR/enable-home"
mkdir -p "$enable_home/.config/omarchy"
cat >"$enable_home/.config/omarchy/shell.json" <<'JSON'
{
  "version": 1,
  "bar": { "layout": { "center": [{ "id": "omarchy.clock" }], "right": [{ "id": "omarchy.tray" }] } },
  "plugins": []
}
JSON

widget_repo="$TMPDIR/widget-repo"
write_plugin "$widget_repo" "acme.widget" "Widget" "right"
commit_plugin "$widget_repo"

HOME="$enable_home" OMARCHY_PATH="$ROOT" PATH="$stub_dir:$ROOT/bin:$PATH" \
  omarchy-plugin-add "$widget_repo" --yes --enable >/dev/null 2>&1 ||
  fail "plugin add --enable places a bar widget without a running shell"

layout=$(jq -c '[.bar.layout.right[] | .id // .]' "$enable_home/.config/omarchy/shell.json")
[[ $layout == '["omarchy.tray","acme.widget"]' ]] ||
  fail "plugin add --enable places a bar widget in its default section" "$layout"
pass "plugin add --enable places a bar widget without a running shell"
