#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
mkdir -p "$TMPDIR/home/.config/omarchy" "$TMPDIR/bin"

cat >"$TMPDIR/bin/omarchy-plugin-hyprland-sync" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH
chmod +x "$TMPDIR/bin/omarchy-plugin-hyprland-sync"

run_state() {
  HOME="$TMPDIR/home" \
    OMARCHY_TEST_CALLS="$TMPDIR/calls" \
    PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
    omarchy-plugin-hyprland-set-enabled "$@"
}

run_state catlee.vim-bindings true >/dev/null
jq -e '.enabled == ["catlee.vim-bindings"]' "$TMPDIR/home/.config/omarchy/hypr-plugins.json" >/dev/null \
  || fail "state command did not enable the plugin"
pass "state command enables a Hyprland plugin"

run_state catlee.vim-bindings false >/dev/null
jq -e '.enabled == []' "$TMPDIR/home/.config/omarchy/hypr-plugins.json" >/dev/null \
  || fail "state command did not disable the plugin"
pass "state command disables a Hyprland plugin"

[[ $(wc -l <"$TMPDIR/calls") -eq 2 ]] || fail "state command synchronized after each change"
pass "state command synchronizes after each change"
