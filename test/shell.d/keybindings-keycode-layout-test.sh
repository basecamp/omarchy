#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash

if [[ $1 == "getoption" ]]; then
  printf '{"str":"%s"}\n' "${TEST_LAYOUTS:-us}"
elif [[ $1 == "devices" ]]; then
  printf '{"keyboards":[{"main":true,"active_layout_index":%s}]}\n' "${TEST_LAYOUT_INDEX:-0}"
fi
SH
chmod +x "$mock_bin/hyprctl"

cat >"$mock_bin/xkbcli" <<'SH'
#!/bin/bash

layout=us
while (($#)); do
  if [[ $1 == "--layout" ]]; then
    layout=$2
    shift 2
  else
    shift
  fi
done

case $layout in
es) symbols="apostrophe exclamdown" ;;
*) symbols="minus equal" ;;
esac
read -r ae11 ae12 <<<"$symbols"

cat <<KEYMAP
xkb_keycodes {
  <AE11> = 20;
  <AE12> = 21;
};
xkb_symbols {
  key <AE11> { [ $ae11 ] };
  key <AE12> { [ $ae12 ] };
};
KEYMAP
SH
chmod +x "$mock_bin/xkbcli"

eval "$(sed -n '/^active_keyboard_layout()/,/^}/p; /^parse_keycodes()/,/^}/p' "$ROOT/bin/omarchy-menu-keybindings")"

resolved=$(PATH="$mock_bin:$PATH" TEST_LAYOUTS=es printf 'SUPER + code:20\n' | PATH="$mock_bin:$PATH" TEST_LAYOUTS=es parse_keycodes)
[[ $resolved == "SUPER + APOSTROPHE" ]] || fail "Spanish keycodes use Spanish symbols" "$resolved"
pass "Spanish keycodes use Spanish symbols"

resolved=$(PATH="$mock_bin:$PATH" TEST_LAYOUTS=us,es TEST_LAYOUT_INDEX=1 printf 'SUPER + code:21\n' | PATH="$mock_bin:$PATH" TEST_LAYOUTS=us,es TEST_LAYOUT_INDEX=1 parse_keycodes)
[[ $resolved == "SUPER + EXCLAMDOWN" ]] || fail "the active layout in a group chooses keycode symbols" "$resolved"
pass "the active layout in a group chooses keycode symbols"

resolved=$(PATH="$mock_bin:$PATH" TEST_LAYOUTS=us TEST_LAYOUT_INDEX=0 printf 'SUPER + code:20\n' | PATH="$mock_bin:$PATH" TEST_LAYOUTS=us TEST_LAYOUT_INDEX=0 parse_keycodes)
[[ $resolved == "SUPER + MINUS" ]] || fail "US keycode symbols remain unchanged" "$resolved"
pass "US keycode symbols remain unchanged"
