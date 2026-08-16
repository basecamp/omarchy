#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

export PATH="$ROOT/bin:$PATH"

TMPDIR=""

cleanup() {
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
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

# Chromium ships in the base packages, so fresh installs do not go through
# omarchy-install-browser, and they mark every migration as already applied.
# The user install still has to register the host itself.
grep -q 'user/chromium.sh' "$ROOT/install/user/all.sh" ||
  fail "user install runs the Chromium native messaging host setup"

fresh_home="$TMPDIR/fresh-install"
HOME="$fresh_home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  bash -euo pipefail -c 'source "$ROOT/install/user/chromium.sh"'

[[ -f $fresh_home/.config/chromium/NativeMessagingHosts/com.omarchy.copy_url.json ]] ||
  fail "fresh install registers the copy-url native messaging host"
pass "fresh install registers the copy-url native messaging host"

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
