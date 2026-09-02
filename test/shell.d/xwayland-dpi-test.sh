#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

stub_bin="$test_dir/bin"
mkdir -p "$stub_bin"
property="$test_dir/property"
set_log="$test_dir/set"

# Answers the read with a canned C-string literal, the way xprop prints it, and
# records what a -set call would have written.
cat >"$stub_bin/xprop" <<STUB
#!/bin/bash
if [[ " \$* " == *" -set "* ]]; then
  printf '%s' "\${@: -1}" >"$set_log"
  exit 0
fi
if [[ -s "$property" ]]; then
  printf 'RESOURCE_MANAGER = "%s"\n' "\$(cat "$property")"
fi
STUB
chmod +x "$stub_bin/xprop"

run() {
  rm -f "$set_log"
  env -i PATH="$stub_bin:/usr/bin" "$@" "$ROOT/bin/omarchy-hyprland-xwayland-dpi"
}

marker='! Xft.dpi is managed by omarchy-hyprland-xwayland-dpi'

: >"$property"
run DISPLAY=:0 GDK_SCALE=2
[[ -f $set_log ]] || fail "no property written on an empty RESOURCE_MANAGER"
[[ $(cat "$set_log") == "$marker"$'\nXft.dpi:\t192' ]] ||
  fail "unexpected resources for GDK_SCALE=2" "$(cat "$set_log")"
pass "publishes Xft.dpi as 96 times GDK_SCALE"

run DISPLAY=:0
[[ $(cat "$set_log") == *$'Xft.dpi:\t96' ]] || fail "GDK_SCALE unset should mean 96 dpi" "$(cat "$set_log")"
pass "falls back to 96 dpi without GDK_SCALE"

run GDK_SCALE=2
[[ ! -f $set_log ]] || fail "wrote a property with no X display"
pass "does nothing without DISPLAY"

printf 'Xcursor.size:\\t48\\n' >"$property"
run DISPLAY=:0 GDK_SCALE=2
[[ $(cat "$set_log") == $'Xcursor.size:\t48\n'"$marker"$'\nXft.dpi:\t192' ]] ||
  fail "other resources were not kept" "$(cat "$set_log")"
pass "keeps resources a user loaded with xrdb"

printf 'Xft.dpi:\\t144\\n' >"$property"
run DISPLAY=:0 GDK_SCALE=2
[[ ! -f $set_log ]] || fail "overwrote a user-set Xft.dpi" "$(cat "$set_log")"
pass "leaves a user-set Xft.dpi alone"

printf 'Xcursor.size:\\t48\\n%s\\nXft.dpi:\\t192\\n' "$marker" >"$property"
run DISPLAY=:0 GDK_SCALE=3
[[ $(cat "$set_log") == $'Xcursor.size:\t48\n'"$marker"$'\nXft.dpi:\t288' ]] ||
  fail "did not replace its own earlier value" "$(cat "$set_log")"
pass "replaces the value it wrote when the scale changes"

service="$ROOT/default/systemd/user/omarchy-fcitx5.service"
grep -Fx 'ExecStartPre=-/usr/bin/omarchy-hyprland-xwayland-dpi' "$service" >/dev/null ||
  fail "fcitx5 unit does not publish Xft.dpi before starting"
pass "fcitx5 unit publishes Xft.dpi before fcitx5 starts"
