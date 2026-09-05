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
printf '%s\n' "$*" >"$WL_COPY_ARGS_OUT"
cat >"$WL_COPY_OUT"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/sleep"

WL_COPY_OUT="$TMPDIR/copy" WL_COPY_ARGS_OUT="$TMPDIR/copy.args" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀"

[[ $(<"$TMPDIR/copy") == "😀" ]] || fail "emoji insert helper copies emoji to clipboard"
pass "emoji insert helper copies emoji to clipboard"

# Without --foreground, wl-copy daemonizes and the content persists instead of
# being cleared after 0.35s by a kill — the root cause of both #7378 (keyboard)
# and #7379 (mouse) where the emoji ended up in neither the clipboard nor the
# target window.
[[ $(<"$TMPDIR/copy.args") == "--type text/plain" ]] ||
  fail "emoji insert helper copies persistently without --foreground" "args: $(<"$TMPDIR/copy.args")"
pass "emoji insert helper copies persistently without --foreground"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "emoji insert helper pastes with shift insert"
pass "emoji insert helper pastes with shift insert"
