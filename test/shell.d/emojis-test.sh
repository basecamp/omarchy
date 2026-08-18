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

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
args="$*"
target="$WL_COPY_OUT"
if [[ $args == "--type text/plain --sensitive --foreground" ]]; then
  target="$WL_COPY_EMOJI_OUT"
fi

printf '%s\n' "$args" >"$target.args"
cat >"$target"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/hyprctl" "$TMPDIR/bin/sleep"

WL_COPY_OUT="$TMPDIR/copy" WL_COPY_EMOJI_OUT="$TMPDIR/emoji" WTYPE_OUT="$TMPDIR/wtype" \
  HYPRCTL_OUT="$TMPDIR/hyprctl" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀"

[[ $(<"$TMPDIR/emoji") == "😀" ]] || fail "emoji insert helper copies emoji transiently"
pass "emoji insert helper copies emoji transiently"

[[ $(<"$TMPDIR/emoji.args") == "--type text/plain --sensitive --foreground" ]] || fail "emoji insert helper serves sensitive transient clipboard in foreground"
pass "emoji insert helper serves transient clipboard in foreground"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "emoji insert helper pastes with shift insert"
pass "emoji insert helper pastes with shift insert"

# With a focus address, the helper restores that window's focus before pasting.
# No hyprctl call is expected without one, so the stub stays empty here.
[[ ! -s "$TMPDIR/hyprctl" ]] || fail "emoji insert helper skips focus restore without a focus address"
pass "emoji insert helper skips focus restore without a focus address"

WL_COPY_OUT="$TMPDIR/copy" WL_COPY_EMOJI_OUT="$TMPDIR/emoji2" WTYPE_OUT="$TMPDIR/wtype2" \
  HYPRCTL_OUT="$TMPDIR/hyprctl" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀" "0x1234abcd"

[[ $(<"$TMPDIR/hyprctl") == 'dispatch hl.dsp.focus({ window = "address:0x1234abcd" })' ]] \
  || fail "emoji insert helper restores the focus captured at picker open"
pass "emoji insert helper restores the focus captured at picker open"
