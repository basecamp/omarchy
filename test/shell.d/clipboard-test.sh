#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const clipboard = requireFromRoot('shell/plugins/clipboard/ClipboardHistory.js')

assertDeepEqual(
  clipboard.normalizeEntry('hello'),
  { type: 'text', text: 'hello' },
  'clipboard normalizes string entries'
)

assertDeepEqual(
  clipboard.normalizeEntry({ kind: 'image', path: '/tmp/a.png' }),
  { type: 'image', path: '/tmp/a.png', mime: 'image/png' },
  'clipboard normalizes image entries with default mime'
)

assertDeepEqual(
  clipboard.parseHistory(JSON.stringify(['one', '', { type: 'text', text: 'two' }, { type: 'image', path: '/tmp/a.jpg', mime: 'image/jpeg' }])),
  [
    { type: 'text', text: 'one' },
    { type: 'text', text: 'two' },
    { type: 'image', path: '/tmp/a.jpg', mime: 'image/jpeg' }
  ],
  'clipboard history parser drops invalid entries'
)

assertDeepEqual(clipboard.parseHistory(JSON.stringify([' ', '\n', { type: 'text', text: '\t' }])), [], 'clipboard history parser drops whitespace-only text')

const history = [
  { type: 'text', text: 'old' },
  { type: 'text', text: 'new' },
  { type: 'image', path: '/tmp/a.png', mime: 'image/png' }
]

assertDeepEqual(
  clipboard.addEntry(history, { type: 'text', text: 'new' }, 100),
  [
    { type: 'text', text: 'new' },
    { type: 'text', text: 'old' },
    { type: 'image', path: '/tmp/a.png', mime: 'image/png' }
  ],
  'clipboard addEntry moves duplicate text to front'
)

assertDeepEqual(
  clipboard.removeEntryAt(history, 1),
  [
    { type: 'text', text: 'old' },
    { type: 'image', path: '/tmp/a.png', mime: 'image/png' }
  ],
  'clipboard removeEntryAt removes the requested entry'
)

assertDeepEqual(clipboard.removeEntryAt(history, 10), history, 'clipboard removeEntryAt ignores invalid indexes')
assertDeepEqual(clipboard.clearHistory(), [], 'clipboard clearHistory returns an empty history')

assertDeepEqual(
  clipboard.displayRows(history, 'image', 50).map(row => ({ type: row.entryType, preview: row.previewText, mime: row.mime })),
  [{ type: 'image', preview: 'Image', mime: 'image/png' }],
  'clipboard display rows search image metadata'
)

assertDeepEqual(
  clipboard.displayRows(history, 'image', 50).map(row => row.index),
  [2],
  'clipboard display rows preserve original history indexes'
)

assertDeepEqual(
  clipboard.displayRows([{ type: 'text', text: 'line one\nline two' }], '', 50)[0].previewText,
  'line one line two',
  'clipboard display rows collapse text whitespace'
)

assertDeepEqual(clipboard.displayRows(history, '', 0), [], 'clipboard display rows supports zero result limit')
assertDeepEqual(clipboard.addEntry(history, 'next', 0), [], 'clipboard addEntry supports zero history limit')
JS

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin" "$TMPDIR/home/.local/state/omarchy"

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
cat >"$WL_COPY_OUT"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype"

jq -n --arg text "$(printf 'large block line 1\nlarge block line 2\n')" '[{type:"text", text:"ignored"}, {type:"text", text:$text}]' >"$TMPDIR/home/.local/state/omarchy/clipboard-history.json"

WL_COPY_OUT="$TMPDIR/copied" WTYPE_OUT="$TMPDIR/wtype" HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-text" --shift-insert --history-index 1

[[ $(<"$TMPDIR/copied") == "$(printf 'large block line 1\nlarge block line 2')" ]] || fail "clipboard paste helper copies history entry text"
pass "clipboard paste helper copies history entry text"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "clipboard paste helper pastes history entries with shift insert"
pass "clipboard paste helper pastes history entries with shift insert"

rm -f "$TMPDIR/wtype"
WL_COPY_OUT="$TMPDIR/copied" WTYPE_OUT="$TMPDIR/wtype" HOME="$TMPDIR/home" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-text" --copy-only --history-index 1

[[ $(<"$TMPDIR/copied") == "$(printf 'large block line 1\nlarge block line 2')" ]] || fail "clipboard paste helper copy-only copies history entry text"
pass "clipboard paste helper copy-only copies history entry text"

[[ ! -e "$TMPDIR/wtype" ]] || fail "clipboard paste helper copy-only skips typing"
pass "clipboard paste helper copy-only skips typing"

printf 'image-data' >"$TMPDIR/image.png"
rm -f "$TMPDIR/wtype"
WL_COPY_OUT="$TMPDIR/copied" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-clipboard-paste-file" --copy-only image/png "$TMPDIR/image.png"

[[ $(<"$TMPDIR/copied") == "image-data" ]] || fail "clipboard file paste helper copy-only copies file content"
pass "clipboard file paste helper copy-only copies file content"

[[ ! -e "$TMPDIR/wtype" ]] || fail "clipboard file paste helper copy-only skips paste keystroke"
pass "clipboard file paste helper copy-only skips paste keystroke"
