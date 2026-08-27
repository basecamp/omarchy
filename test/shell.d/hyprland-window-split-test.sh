#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

if [[ $1 == "activeworkspace" ]]; then
  printf '{"id":1,"tiledLayout":"%s"}\n' "$HYPRCTL_LAYOUT"
else
  printf '%s\n' "$*" >>"$HYPRCTL_LOG"
fi
EOF
chmod +x "$stub_dir/hyprctl"

HYPRCTL_LAYOUT=dwindle HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-window-split-toggle"

grep -F 'dispatch hl.dsp.layout("togglesplit")' "$log_file" >/dev/null ||
  fail "split toggle uses togglesplit on dwindle layout"
pass "split toggle uses togglesplit on dwindle layout"

: >"$log_file"
HYPRCTL_LAYOUT=scrolling HYPRCTL_LOG="$log_file" PATH="$stub_dir:$PATH" \
  "$ROOT/bin/omarchy-hyprland-window-split-toggle"

grep -F 'dispatch hl.dsp.layout("promote")' "$log_file" >/dev/null ||
  fail "split toggle uses promote on scrolling layout"
! grep -F 'togglesplit' "$log_file" >/dev/null ||
  fail "split toggle does not dispatch togglesplit on scrolling layout"
pass "split toggle uses promote on scrolling layout"
