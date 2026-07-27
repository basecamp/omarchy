#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command python3

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/home/.config/omarchy"

clone() {
  HOME="$TMPDIR/home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    omarchy-plugin-clone "$1" "$2" --name "$3"
}

# A bar widget that pulls in a sibling JS module clones into a directory that
# does not contain it, so the import has to be rewritten back to the bundled
# file or the cloned widget fails to load.
clone omarchy.clock local.clock-clone "Cloned Clock" >/dev/null
widget="$TMPDIR/home/.config/omarchy/plugins/local.clock-clone/Widget.qml"

[[ -f $widget ]] || fail "clone produces a widget file"
pass "clone produces a widget file"

grep -q 'moduleName: "local.clock-clone"' "$widget" ||
  fail "clone rewrites the module name"
pass "clone rewrites the module name"

while read -r ref; do
  [[ $ref == file://* ]] || fail "clone leaves a relative reference behind" "$ref"
done < <(grep -oE '(import|Qt\.resolvedUrl\() *"[^"]+"' "$widget" |
  grep -oE '"[^"]+"' | tr -d '"' | grep -E '\.(js|qml)$')
pass "clone resolves every relative QML and JS reference to the bundled file"

for ref in $(grep -oE 'file://[^"]+\.(js|qml)' "$widget"); do
  path=${ref#file://}
  [[ -f $path ]] || fail "cloned reference points at a real file" "$ref"
done
pass "cloned references point at files that exist"

# The bundled widget genuinely has such an import, so the check above is not
# passing by accident.
grep -qE '^import "[^"/][^"]*\.js"' "$ROOT/shell/plugins/panels/clock/BarWidget.qml" ||
  fail "the clock widget still imports a sibling JS module"
pass "the clock widget still imports a sibling JS module"
