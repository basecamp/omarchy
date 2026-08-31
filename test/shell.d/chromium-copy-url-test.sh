#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

export PATH="$ROOT/bin:$PATH"

test_tmp=""

cleanup() {
  if [[ -n $test_tmp && -d $test_tmp ]]; then
    rm -rf "$test_tmp"
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
  .background.service_worker == "background-5.js" and
  .commands["subscribe-feed"].suggested_key.default == "Alt+Shift+F"
' "$ROOT/default/chromium/extensions/copy-url/manifest.json" >/dev/null ||
  fail "browser actions extension exposes copy and feed commands through its native host"
grep -q "sendNativeMessage('com.omarchy.copy_url'" \
  "$ROOT/default/chromium/extensions/copy-url/background-5.js" ||
  fail "browser actions extension sends URLs to its native messaging host"
grep -q "command !== 'copy-url' && command !== 'subscribe-feed'" \
  "$ROOT/default/chromium/extensions/copy-url/background-5.js" ||
  fail "browser actions extension accepts the feed subscription command"
pass "browser actions extension routes copy and feed commands"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const source = fs.readFileSync(path.join(root, 'default/chromium/extensions/copy-url/background-5.js'), 'utf8')
let commandListener
let actionListener
let queried = 0
const messages = []
const context = {
  chrome: {
    runtime: {
      lastError: undefined,
      sendNativeMessage(host, payload, callback) {
        messages.push({host, payload})
        callback()
      },
    },
    commands: {onCommand: {addListener(listener) { commandListener = listener }}},
    tabs: {query(options, callback) {
      queried += 1
      assertDeepEqual(options, {active: true, currentWindow: true}, 'browser action queries only the active tab')
      callback([{url: 'https://example.test/current?page=1'}])
    }},
    action: {onClicked: {addListener(listener) { actionListener = listener }}},
  },
}
vm.runInNewContext(source, context)
assert(typeof commandListener === 'function' && typeof actionListener === 'function', 'browser action registers command and toolbar listeners')

commandListener('subscribe-feed')
assertEqual(queried, 1, 'Subscribe to Feeds resolves the active browser tab')
assertDeepEqual(messages[0], {
  host: 'com.omarchy.copy_url',
  payload: {action: 'subscribe-feed', url: 'https://example.test/current?page=1'},
}, 'Subscribe to Feeds sends the active URL through native messaging')

commandListener('unknown-command')
assertEqual(queried, 1, 'unknown extension commands never inspect browser tabs')
assertEqual(messages.length, 1, 'unknown extension commands never reach the native host')

actionListener({url: 'https://example.test/toolbar'})
assertDeepEqual(messages[1], {
  host: 'com.omarchy.copy_url',
  payload: {action: 'copy-url', url: 'https://example.test/toolbar'},
}, 'toolbar activation keeps the original Copy URL behavior')

actionListener({})
assertEqual(messages.length, 2, 'a tab without a URL never reaches the native host')
pass('browser actions execute the copy and subscription routes')
JS

jq -e '.action != null' "$ROOT/default/chromium/extensions/copy-url/manifest.json" >/dev/null &&
  grep -q 'action.onClicked' "$ROOT/default/chromium/extensions/copy-url/"background-*.js ||
  fail "copy-url extension is clickable from the toolbar"
pass "copy-url extension is clickable from the toolbar"

test_tmp=$(mktemp -d)
test_home="$test_tmp/home"
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

fresh_home="$test_tmp/fresh-install"
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

subscribe_log="$test_tmp/subscribed-url"
export SUBSCRIBE_LOG="$subscribe_log"
bash -c '
  source "$1"
  omarchy-newsboat-subscribe() { printf "%s" "$1" >"$SUBSCRIBE_LOG"; }
  subscribe_url "$2"
' bash "$ROOT/bin/omarchy-chromium-copy-url-host" 'https://example.test/articles/latest'

[[ $(<"$subscribe_log") == "https://example.test/articles/latest" ]] ||
  fail "browser native host passes the complete page URL to feed discovery" "$(<"$subscribe_log")"
pass "browser native host dispatches feed subscriptions"

if bash -c '
  source "$1"
  omarchy-newsboat-subscribe() { return 0; }
  subscribe_url "$2"
' bash "$ROOT/bin/omarchy-chromium-copy-url-host" 'chrome://settings'; then
  fail "browser native host rejects non-web subscription pages"
fi
pass "browser native host limits subscription discovery to web pages"

native_root="$test_tmp/native-root"
native_log="$test_tmp/native-subscriptions"
mkdir -p "$native_root/bin"
cat >"$native_root/bin/omarchy-newsboat-subscribe" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >>"$NATIVE_TEST_SUBSCRIBE_LOG"
exit "${NATIVE_TEST_SUBSCRIBE_STATUS:-0}"
SH
chmod +x "$native_root/bin/omarchy-newsboat-subscribe"
export NATIVE_TEST_HOST="$ROOT/bin/omarchy-chromium-copy-url-host"
export NATIVE_TEST_ROOT="$native_root"
export NATIVE_TEST_SUBSCRIBE_LOG="$native_log"

run_node_test <<'JS'
const {spawnSync} = require('child_process')

function invoke(message, extraEnv = {}) {
  const payload = Buffer.from(JSON.stringify(message))
  const header = Buffer.alloc(4)
  header.writeUInt32LE(payload.length)
  const result = spawnSync(process.env.NATIVE_TEST_HOST, {
    input: Buffer.concat([header, payload]),
    env: {...process.env, ...extraEnv, OMARCHY_PATH: process.env.NATIVE_TEST_ROOT},
  })
  assertEqual(result.status, 0, 'native messaging host exits cleanly after a framed request')
  assert(
    result.stdout.length >= 4,
    'native messaging host returns a framed response',
    result.stderr.toString('utf8'),
  )
  const length = result.stdout.readUInt32LE(0)
  assertEqual(result.stdout.length, length + 4, 'native messaging response length matches its frame')
  return JSON.parse(result.stdout.subarray(4).toString('utf8'))
}

assertDeepEqual(
  invoke({action: 'subscribe-feed', url: 'https://example.test/article?one=1&two=2'}),
  {subscribed: true},
  'framed subscription requests report native-host success',
)
assertDeepEqual(
  invoke({action: 'subscribe-feed', url: 'https://example.test/failure'}, {NATIVE_TEST_SUBSCRIBE_STATUS: '9'}),
  {subscribed: false},
  'subscription helper failures return a framed failure',
)
assertDeepEqual(
  invoke({action: 'subscribe-feed', url: 'chrome://settings'}),
  {subscribed: false},
  'framed subscription requests reject non-web pages',
)
assertDeepEqual(
  invoke({action: 'unknown', url: 'https://example.test'}),
  {copied: false},
  'unknown native actions fail closed',
)

const shortHeader = spawnSync(process.env.NATIVE_TEST_HOST, {
  input: Buffer.from([1, 2]),
  env: {...process.env, OMARCHY_PATH: process.env.NATIVE_TEST_ROOT},
})
assertEqual(shortHeader.status, 0, 'truncated native frames exit cleanly')
assertEqual(shortHeader.stdout.length, 0, 'truncated native frames publish no decision')

const oversizedHeader = Buffer.alloc(4)
oversizedHeader.writeUInt32LE(1048577)
const oversized = spawnSync(process.env.NATIVE_TEST_HOST, {
  input: oversizedHeader,
  env: {...process.env, OMARCHY_PATH: process.env.NATIVE_TEST_ROOT},
})
assertEqual(oversized.status, 0, 'oversized native frames exit cleanly')
assertEqual(oversized.stdout.length, 0, 'oversized native frames are rejected before reading a payload')
pass('native messaging executes and bounds the complete subscription protocol')
JS

grep -Fxq 'https://example.test/article?one=1&two=2' "$native_log" || fail "native messaging loses URL query parameters"
grep -Fxq 'https://example.test/failure' "$native_log" || fail "native messaging does not invoke the helper before reporting its failure"
if grep -Fq 'chrome://settings' "$native_log"; then
  fail "native messaging invokes subscription discovery for a rejected page"
fi
pass "native messaging passes only complete web URLs to feed discovery"

native_reply=$(bash -c '
  source "$1"
  reply_copied true
' bash "$ROOT/bin/omarchy-chromium-copy-url-host" | od -An -v -tx1 | tr -d ' \n')

[[ $native_reply == "0f0000007b22636f70696564223a747275657d" ]] ||
  fail "copy-url native host returns a framed success response" "$native_reply"
pass "copy-url native host returns a framed success response"
