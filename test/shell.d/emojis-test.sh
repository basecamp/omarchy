#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const emojis = requireFromRoot('shell/plugins/emojis/EmojiSearch.js')

const raw = fs.readFileSync(path.join(root, 'shell/plugins/emojis/emojis.json'), 'utf8')
const data = emojis.parseEmojis(raw)

assert(data.length > 1000, 'emoji dataset parses')
assertDeepEqual(emojis.parseEmojis('{'), [], 'invalid emoji JSON parses as empty list')
assertDeepEqual(emojis.parseEmojis('{"e":"nope"}'), [], 'non-array emoji JSON parses as empty list')

const fixture = [
  { e: 'a', k: 'grinning face smile happy' },
  { e: 'b', k: 'face with tears of joy joy tears' },
  { e: 'c', k: 'flag: united states us america' }
]

assertDeepEqual(
  emojis.filterEmojis(fixture, '  JOY  ').map(item => item.e),
  ['b'],
  'emoji filtering trims and lowercases query'
)

assertDeepEqual(
  emojis.filterEmojis(fixture, '', 2).map(item => item.e),
  ['a', 'b'],
  'emoji filtering honors result limit'
)

assertDeepEqual(
  emojis.filterEmojis(fixture, '', 0),
  [],
  'emoji filtering supports zero result limit'
)

assertEqual(
  emojis.filterEmojis(data, 'face with tears')[0].e,
  '\u{1F602}',
  'emoji filtering finds face with tears of joy'
)
JS

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SLEEP_OUT"
SH

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
cat >"$WLCOPY_OUT"
SH

cat >"$TMPDIR/bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_OUT"
case "$*" in
  *activewindow*)
    if [[ -n $HYPRCTL_ACTIVE ]]; then
      printf '%s\n' "$HYPRCTL_ACTIVE"
    else
      printf '{"address": "%s", "tags": [%s]}\n' "${HYPRCTL_ADDRESS:-0x0}" "${HYPRCTL_TAGS:-}"
    fi
    ;;
esac
SH

chmod +x "$TMPDIR/bin/wtype" "$TMPDIR/bin/sleep" "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/hyprctl"

term_env=(WTYPE_OUT="$TMPDIR/wtype" SLEEP_OUT="$TMPDIR/sleep" HYPRCTL_OUT="$TMPDIR/hyprctl" WLCOPY_OUT="$TMPDIR/wlcopy" PATH="$TMPDIR/bin:$PATH")

# A terminal is tagged "terminal" (dynamic tags carry a trailing "*").
env "${term_env[@]}" HYPRCTL_TAGS='"default-opacity*", "terminal*"' \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀" "0xdeadbeef"

[[ $(<"$TMPDIR/wtype") == "😀" ]] || fail "emoji insert helper types the emoji into a focused terminal"
pass "emoji insert helper types the emoji into a focused terminal"

[[ -s "$TMPDIR/sleep" ]] || fail "emoji insert helper waits for focus to settle before inserting"
pass "emoji insert helper waits for focus to settle before inserting"

[[ ! -e "$TMPDIR/wlcopy" ]] || fail "emoji insert helper leaves the clipboard alone for a terminal"
pass "emoji insert helper leaves the clipboard alone for a terminal"

grep -qF 'hl.dsp.focus({ window = "address:0xdeadbeef" })' "$TMPDIR/hyprctl" || fail "emoji insert helper refocuses the picker's origin window by address"
pass "emoji insert helper refocuses the picker's origin window by address"

# A bare (0x-less) address is normalised before dispatch.
: >"$TMPDIR/hyprctl"
env "${term_env[@]}" WTYPE_OUT="$TMPDIR/wtype2" SLEEP_OUT="$TMPDIR/sleep2" HYPRCTL_TAGS='"terminal*"' \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀" "deadbeef"
grep -qF 'address:0xdeadbeef' "$TMPDIR/hyprctl" || fail "emoji insert helper normalises a bare window address"
pass "emoji insert helper normalises a bare window address"

# Refocus loop stops once the origin window is active again.
: >"$TMPDIR/hyprctl"
env "${term_env[@]}" WTYPE_OUT="$TMPDIR/wtype3" SLEEP_OUT="$TMPDIR/sleep3" \
  HYPRCTL_ACTIVE='{"address": "0xdeadbeef", "tags": ["terminal*"]}' \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀" "0xdeadbeef"
! grep -q "address:" "$TMPDIR/hyprctl" || fail "emoji insert helper stops refocusing once the origin window is active"
pass "emoji insert helper stops refocusing once the origin window is active"

# A non-terminal window (here a browser) gets a clipboard paste, not injected
# Unicode - Chromium and Electron apps drop wtype's transient keymap.
: >"$TMPDIR/hyprctl"
env "${term_env[@]}" WTYPE_OUT="$TMPDIR/wtype-gui" WLCOPY_OUT="$TMPDIR/wlcopy-gui" \
  HYPRCTL_TAGS='"default-opacity*", "firefox-based-browser*"' \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀" "0xdeadbeef"

[[ $(<"$TMPDIR/wlcopy-gui") == "😀" ]] || fail "emoji insert helper puts the emoji on the clipboard for a GUI app"
pass "emoji insert helper puts the emoji on the clipboard for a GUI app"

grep -q "ctrl" "$TMPDIR/wtype-gui" || fail "emoji insert helper sends Ctrl+V to paste into a GUI app"
pass "emoji insert helper sends Ctrl+V to paste into a GUI app"

[[ $(<"$TMPDIR/wtype-gui") != "😀" ]] || fail "emoji insert helper does not inject raw Unicode into a GUI app"
pass "emoji insert helper does not inject raw Unicode into a GUI app"

# An untagged window falls back to the paste path.
: >"$TMPDIR/hyprctl"
env "${term_env[@]}" WTYPE_OUT="$TMPDIR/wtype-untagged" WLCOPY_OUT="$TMPDIR/wlcopy-untagged" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀" "0xdeadbeef"
[[ $(<"$TMPDIR/wlcopy-untagged") == "😀" ]] || fail "emoji insert helper defaults to paste for an untagged window"
pass "emoji insert helper defaults to paste for an untagged window"

# No origin window recorded: still inserts, but dispatches no focus change.
env "${term_env[@]}" WTYPE_OUT="$TMPDIR/wtype-notarget" HYPRCTL_OUT="$TMPDIR/hyprctl-notarget" \
  HYPRCTL_TAGS='"terminal*"' \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀"

[[ $(<"$TMPDIR/wtype-notarget") == "😀" ]] || fail "emoji insert helper still inserts without a window address"
pass "emoji insert helper still inserts without a window address"

! grep -qE 'dsp\.focus|dispatch focuswindow' "$TMPDIR/hyprctl-notarget" || fail "emoji insert helper skips refocus without a window address"
pass "emoji insert helper skips refocus without a window address"

env "${term_env[@]}" WTYPE_OUT="$TMPDIR/wtype-noarg" SLEEP_OUT="$TMPDIR/sleep-noarg" \
  HYPRCTL_OUT="$TMPDIR/hyprctl-noarg" WLCOPY_OUT="$TMPDIR/wlcopy-noarg" \
  "$ROOT/bin/omarchy-menu-emoji-insert" ""

[[ ! -e "$TMPDIR/wtype-noarg" ]] || fail "emoji insert helper does nothing without an emoji argument"
pass "emoji insert helper does nothing without an emoji argument"

[[ ! -e "$TMPDIR/sleep-noarg" ]] || fail "emoji insert helper exits before sleeping without an emoji argument"
pass "emoji insert helper exits before sleeping without an emoji argument"

[[ ! -e "$TMPDIR/hyprctl-noarg" ]] || fail "emoji insert helper exits before querying hyprctl without an emoji argument"
pass "emoji insert helper exits before querying hyprctl without an emoji argument"
