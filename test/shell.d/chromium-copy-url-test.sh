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

jq -e '
  .manifest_version == 3 and
  (.permissions | index("nativeMessaging")) and
  (.permissions | index("notifications") | not) and
  (.permissions | index("clipboardWrite") | not) and
  (.permissions | index("offscreen") | not) and
  .background.service_worker == "background-4.js"
' "$ROOT/default/chromium/extensions/copy-url/manifest.json" >/dev/null ||
  fail "copy-url extension uses its native messaging host"
grep -q "sendNativeMessage('com.omarchy.copy_url'" \
  "$ROOT/default/chromium/extensions/copy-url/background-4.js" ||
  fail "copy-url extension sends URLs to its native messaging host"
pass "copy-url extension uses its native messaging host"

jq -e '.action != null' "$ROOT/default/chromium/extensions/copy-url/manifest.json" >/dev/null &&
  grep -q 'action.onClicked' "$ROOT/default/chromium/extensions/copy-url/"background-*.js ||
  fail "copy-url extension is clickable from the toolbar"
pass "copy-url extension is clickable from the toolbar"

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
native_manifest="$test_home/.config/chromium/NativeMessagingHosts/com.omarchy.copy_url.json"

HOME="$test_home" OMARCHY_PATH="$ROOT" omarchy-install-chromium-copy-url

[[ -f $native_manifest ]] || fail "copy-url native host installer creates fresh Chromium profile root"
jq -e --arg path "$ROOT/bin/omarchy-chromium-copy-url-host" '
  .name == "com.omarchy.copy_url" and
  .path == $path and
  (.allowed_origins | index("chrome-extension://bgpiichlckmfanooecilcjemknkcpngb/"))
' "$native_manifest" >/dev/null || fail "copy-url native host manifest uses Omarchy host path and extension id"
pass "copy-url native host installer registers the stable extension id"

copied_url=$(bash -c '
  source "$1"
  wl-copy() { cat; }
  omarchy-notification-send() { :; }
  copy_url "$2"
' bash "$ROOT/bin/omarchy-chromium-copy-url-host" 'https://example.test/path?q=one&name=two')

[[ $copied_url == "https://example.test/path?q=one&name=two" ]] ||
  fail "copy-url native host writes the complete URL" "$copied_url"
pass "copy-url native host writes the complete URL"

native_reply=$(bash -c '
  source "$1"
  reply_copied true
' bash "$ROOT/bin/omarchy-chromium-copy-url-host" | od -An -v -tx1 | tr -d ' \n')

[[ $native_reply == "0f0000007b22636f70696564223a747275657d" ]] ||
  fail "copy-url native host returns a framed success response" "$native_reply"
pass "copy-url native host returns a framed success response"

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
