#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

export PATH="$ROOT/bin:$PATH"

TMPDIR=""

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

require_command jq
require_command node

copy_url_id=$(node - <<'JS' "$ROOT/default/chromium/extensions/copy-url/manifest.json"
const crypto = require('crypto')
const fs = require('fs')

const manifest = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))
const hash = crypto.createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest()
const alphabet = 'abcdefghijklmnop'
let id = ''

for (const byte of hash.subarray(0, 16)) {
  id += alphabet[byte >> 4]
  id += alphabet[byte & 0x0f]
}

process.stdout.write(id)
JS
)

[[ $copy_url_id == "bgpiichlckmfanooecilcjemknkcpngb" ]] ||
  fail "copy-url extension manifest has the stable id" "$copy_url_id"
pass "copy-url extension manifest has the stable id"

TMPDIR=$(mktemp -d)
preferences="$TMPDIR/Preferences"
backup="$TMPDIR/Preferences.bak"
patch_script="$TMPDIR/repair-shortcuts.py"

awk '
  /<<'\''CHROMIUM_SHORTCUTS_PATCH_PY'\''/ { copying = 1; next }
  copying && $0 == "CHROMIUM_SHORTCUTS_PATCH_PY" { exit }
  copying { print }
' "$ROOT/bin/omarchy-upgrade-to-quattro" >"$patch_script"

cat >"$preferences" <<'JSON'
{"extensions":{"commands":{"linux:Alt+Shift+L":{"command_name":"copy-url","extension":"bocglpkldciamkbmlphanhkfnhpmnbma","global":false},"linux:Alt+Shift+D":{"command_name":"download-video","extension":"dedjgknigfeelejglamclffonmophnfl","global":false}},"settings":{"bocglpkldciamkbmlphanhkfnhpmnbma":{"commands":{"copy-url":{"suggested_key":"Alt+Shift+L","was_assigned":true}}},"bgpiichlckmfanooecilcjemknkcpngb":{"commands":{"copy-url":{"suggested_key":"Alt+Shift+L"}}}}}}
JSON

python3 "$patch_script" "$preferences" "$backup"

jq -e '
  .extensions.commands["linux:Alt+Shift+L"].extension == "bgpiichlckmfanooecilcjemknkcpngb" and
  .extensions.commands["linux:Alt+Shift+D"].extension == "dedjgknigfeelejglamclffonmophnfl" and
  (.extensions.settings.bocglpkldciamkbmlphanhkfnhpmnbma.commands["copy-url"] | has("was_assigned") | not) and
  .extensions.settings.bgpiichlckmfanooecilcjemknkcpngb.commands["copy-url"].was_assigned == true
' "$preferences" >/dev/null || fail "quattro upgrade moves the Copy URL shortcut to the stable extension id"
cmp -s "$backup" <(printf '%s\n' '{"extensions":{"commands":{"linux:Alt+Shift+L":{"command_name":"copy-url","extension":"bocglpkldciamkbmlphanhkfnhpmnbma","global":false},"linux:Alt+Shift+D":{"command_name":"download-video","extension":"dedjgknigfeelejglamclffonmophnfl","global":false}},"settings":{"bocglpkldciamkbmlphanhkfnhpmnbma":{"commands":{"copy-url":{"suggested_key":"Alt+Shift+L","was_assigned":true}}},"bgpiichlckmfanooecilcjemknkcpngb":{"commands":{"copy-url":{"suggested_key":"Alt+Shift+L"}}}}}}') ||
  fail "quattro upgrade backs up Chromium preferences before shortcut repair"
pass "quattro upgrade repairs and backs up the Copy URL shortcut"

unchanged_hash=$(sha256sum "$preferences" | cut -d' ' -f1)
rm "$backup"
python3 "$patch_script" "$preferences" "$backup"
[[ $(sha256sum "$preferences" | cut -d' ' -f1) == "$unchanged_hash" && ! -e $backup ]] ||
  fail "Copy URL shortcut repair is idempotent"
pass "Copy URL shortcut repair is idempotent"
