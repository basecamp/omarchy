#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

export HOME="$TEST_HOME/home"
export XDG_RUNTIME_DIR="$TEST_HOME/run"
export XDG_STATE_HOME="$TEST_HOME/state"
export HYPRLAND_INSTANCE_SIGNATURE=test
mkdir -p "$HOME" "$XDG_RUNTIME_DIR/hypr/test" "$TEST_HOME/bin"

export MOCK_LOG="$TEST_HOME/calls"
export MOCK_LAYOUTS=us,ir
export MOCK_VARIANTS=
export MOCK_ACTIVE_INDEX=1
export MOCK_CURRENT_IM=keyboard-us
export MOCK_GROUP_INFO='{"type":"sssa{sv}a(sssssssbsa{sv})","data":["Default","keyboard-us","us",{},[["keyboard-us","Keyboard - English (US)","","input-keyboard","en","en","keyboard",true,"",{}]]]}'

make_mock() {
  local name=$1 body=$2
  printf '#!/bin/bash\n%s\n' "$body" >"$TEST_HOME/bin/$name"
  chmod +x "$TEST_HOME/bin/$name"
}

make_mock hyprctl 'case "$1:$2" in
  getoption:input:kb_layout) jq -nc --arg str "$MOCK_LAYOUTS" '\''{str:$str}'\'' ;;
  getoption:input:kb_variant) jq -nc --arg str "$MOCK_VARIANTS" '\''{str:$str}'\'' ;;
  devices:-j) jq -nc --argjson index "$MOCK_ACTIVE_INDEX" '\''{keyboards:[{name:"at-translated-set-2-keyboard",active_layout_index:$index},{name:"hl-virtual-keyboard-fcitx5",active_layout_index:0}]}'\'' ;;
esac'

make_mock fcitx5-remote 'case "${1:-}" in
  --check) exit 0 ;;
  -q) echo Default ;;
  -n) echo "$MOCK_CURRENT_IM" ;;
  -s) printf "remote %s\\n" "$2" >>"$MOCK_LOG" ;;
esac'

make_mock busctl 'printf "busctl" >>"$MOCK_LOG"; printf " <%s>" "$@" >>"$MOCK_LOG"; printf "\\n" >>"$MOCK_LOG"
[[ " $* " == *" FullInputMethodGroupInfo "* ]] && printf "%s\\n" "$MOCK_GROUP_INFO"
exit 0'

PATH="$TEST_HOME/bin:$PATH" "$ROOT/bin/omarchy-fcitx5-layout-sync" --once

grep -F '<SetInputMethodGroupInfo> <ssa(ss)> <Default> <us> <2> <keyboard-us> <> <keyboard-ir> <>' "$MOCK_LOG" >/dev/null ||
  fail "the untouched fcitx5 group did not gain every Hyprland keyboard layout"
grep -Fx 'remote keyboard-ir' "$MOCK_LOG" >/dev/null ||
  fail "fcitx5 did not follow the active physical keyboard layout"
grep -Fx 'group=Default' "$XDG_STATE_HOME/omarchy/fcitx5-hyprland-layouts" >/dev/null
grep -Fx 'layout=us' "$XDG_STATE_HOME/omarchy/fcitx5-hyprland-layouts" >/dev/null
grep -Fx 'keyboard-us' "$XDG_STATE_HOME/omarchy/fcitx5-hyprland-layouts" >/dev/null
grep -Fx 'keyboard-ir' "$XDG_STATE_HOME/omarchy/fcitx5-hyprland-layouts" >/dev/null
pass "default fcitx5 group follows Hyprland's active XKB layout"

: >"$MOCK_LOG"
export MOCK_GROUP_INFO='{"type":"sssa{sv}a(sssssssbsa{sv})","data":["Default","pinyin","us",{},[["keyboard-us","Keyboard - English (US)","","input-keyboard","en","en","keyboard",true,"",{}],["pinyin","Pinyin","","input-keyboard","zh","zh","pinyin",true,"",{}]]]}'
rm "$XDG_STATE_HOME/omarchy/fcitx5-hyprland-layouts"

PATH="$TEST_HOME/bin:$PATH" "$ROOT/bin/omarchy-fcitx5-layout-sync" --once

grep -F '<SetInputMethodGroupInfo>' "$MOCK_LOG" >/dev/null &&
  fail "a customized fcitx5 group was overwritten"
pass "custom fcitx5 input-method groups remain user-owned"

: >"$MOCK_LOG"
export MOCK_CURRENT_IM=pinyin

PATH="$TEST_HOME/bin:$PATH" "$ROOT/bin/omarchy-fcitx5-layout-sync" --once

grep -F 'remote keyboard-ir' "$MOCK_LOG" >/dev/null &&
  fail "Hyprland layout changes displaced an active language input method"
pass "active non-keyboard input methods are not displaced"
