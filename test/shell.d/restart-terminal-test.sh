#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
config_home="$test_tmp/xdg-config"
stub_bin="$test_tmp/bin"
mkdir -p "$home/.config/alacritty" "$config_home/alacritty" "$stub_bin"

printf 'legacy\n' >"$home/.config/alacritty/alacritty.toml"
printf 'xdg\n' >"$config_home/alacritty/alacritty.toml"

cat >"$stub_bin/touch" <<'STUB'
#!/bin/bash
printf '%s\n' "$1" >>"$TOUCH_LOG"
STUB
chmod +x "$stub_bin/touch"

cat >"$stub_bin/pgrep" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$stub_bin/pgrep"

cat >"$stub_bin/killall" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$stub_bin/killall"

HOME="$home" XDG_CONFIG_HOME="$config_home" TOUCH_LOG="$test_tmp/touch.log" \
  PATH="$stub_bin:$PATH" "$ROOT/bin/omarchy-restart-terminal"

grep -qxF "$config_home/alacritty/alacritty.toml" "$test_tmp/touch.log" ||
  fail "terminal restart touches the XDG Alacritty config"
! grep -qxF "$home/.config/alacritty/alacritty.toml" "$test_tmp/touch.log" ||
  fail "terminal restart leaves the legacy config untouched"
pass "terminal restart honors XDG_CONFIG_HOME"
