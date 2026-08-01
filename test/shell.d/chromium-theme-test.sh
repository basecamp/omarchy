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

EXT_DIR="$ROOT/default/chromium/extensions/whatsapp-theme"

# The manifest key pins the extension id so the native host manifest's
# allowed_origins can be hardcoded. Derive it the same way Chromium does.
theme_id=$(node - <<'JS' "$EXT_DIR/manifest.json"
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

[[ $theme_id == "ndpkabodcpddojgepdideonokpblpeln" ]] ||
  fail "whatsapp-theme extension manifest has the stable id" "$theme_id"
pass "whatsapp-theme extension manifest has the stable id"

jq -e '
  .manifest_version == 3 and
  (.permissions | index("nativeMessaging")) and
  (.host_permissions | index("*://web.whatsapp.com/*")) and
  .background.service_worker == "background.js" and
  (.content_scripts | map(.world) | index("MAIN")) and
  (.content_scripts | map(.js) | add | index("omarchy-prefers-color-scheme.js")) and
  (.content_scripts | map(.js) | add | index("content.js"))
' "$EXT_DIR/manifest.json" >/dev/null ||
  fail "whatsapp-theme extension declares its host, content script, and prefers-color-scheme shim"
grep -q 'connectNative(HOST)' "$EXT_DIR/background.js" &&
  grep -q '"com.omarchy.theme"' "$EXT_DIR/background.js" ||
  fail "whatsapp-theme extension connects to the com.omarchy.theme bridge"
pass "whatsapp-theme extension follows the theme over native messaging"

# The WhatsApp host permission already grants tab urls and lets tabs.query filter
# by url, so `tabs` would only add every other tab's url and title.
jq -e '(.permissions | index("tabs")) | not' "$EXT_DIR/manifest.json" >/dev/null ||
  fail "whatsapp-theme extension asks for no broader tab access than it needs"
pass "whatsapp-theme extension asks for no broader tab access than it needs"

# Light/dark comes from WCAG relative luminance, which needs each channel
# linearized first. Mid-tones are where weighting the raw bytes diverges.
scheme_check=$(node - "$EXT_DIR/content.js" <<'JS'
const fs = require('fs')
const source = fs.readFileSync(process.argv[2], 'utf8')
const match = source.match(/function channelLuminance[\s\S]*?\n}\n[\s\S]*?function isDarkTheme[\s\S]*?\n}\n/)
if (!match) {
  process.stdout.write('no-classifier')
  process.exit(0)
}
const isDarkTheme = new Function(match[0] + '; return isDarkTheme')()
const cases = [
  ['#1e1e2e', true],   // catppuccin, unambiguously dark
  ['#eff1f5', false],  // catppuccin-latte, unambiguously light
  ['#000000', true],
  ['#ffffff', false],
  ['#808080', true],   // gamma-encoded weighting calls this light
]
const bad = cases.filter(([bg, want]) => isDarkTheme({ bg }) !== want).map(([bg]) => bg)
if (isDarkTheme({ bg: 'nope' }) !== null || isDarkTheme({}) !== null) bad.push('malformed')
process.stdout.write(bad.length ? 'wrong:' + bad.join(',') : 'ok')
JS
)

[[ $scheme_check == "ok" ]] ||
  fail "whatsapp-theme classifies light and dark by linearized luminance" "$scheme_check"
pass "whatsapp-theme classifies light and dark by linearized luminance"

# The shim must preserve the MediaQueryList listener shapes web apps can use,
# including EventListener objects and the onchange property.
listener_check=$(node - "$EXT_DIR/omarchy-prefers-color-scheme.js" <<'JS'
const fs = require('fs')
const vm = require('vm')
let themeChange
const context = {
  window: {
    matchMedia(query) {
      return { matches: query.includes('dark'), media: query }
    },
  },
  document: {
    addEventListener(type, cb) {
      if (type === 'omarchy:set-color-scheme') themeChange = cb
    },
  },
}
vm.runInNewContext(fs.readFileSync(process.argv[2], 'utf8'), context)
const query = context.window.matchMedia('(prefers-color-scheme: dark)')
const calls = []
query.addEventListener('change', { handleEvent: (event) => calls.push(['object', event.matches]) })
query.addEventListener('change', (event) => calls.push(['once', event.matches]), { once: true })
const controller = new AbortController()
query.addEventListener('change', () => calls.push(['aborted']), { signal: controller.signal })
controller.abort()
query.onchange = function (event) {
  calls.push(['onchange', event.matches, this === query])
}
themeChange({ detail: { dark: false } })
themeChange({ detail: { dark: true } })
process.stdout.write(JSON.stringify(calls))
JS
)
[[ $listener_check == '[["object",false],["once",false],["onchange",false,true],["object",true],["onchange",true,true]]' ]] ||
  fail "prefers-color-scheme shim supports listener objects and onchange" "$listener_check"
pass "prefers-color-scheme shim supports listener objects and onchange"

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
native_manifest="$test_home/.config/chromium/NativeMessagingHosts/com.omarchy.theme.json"

HOME="$test_home" OMARCHY_PATH="$ROOT" omarchy-install-chromium-theme

[[ -f $native_manifest ]] || fail "theme native host installer creates fresh Chromium profile root"
jq -e --arg path "$ROOT/bin/omarchy-chromium-theme-host" '
  .name == "com.omarchy.theme" and
  .path == $path and
  (.allowed_origins | index("chrome-extension://ndpkabodcpddojgepdideonokpblpeln/"))
' "$native_manifest" >/dev/null || fail "theme native host manifest uses Omarchy host path and extension id"
pass "theme native host installer registers the stable extension id"

# Chromium ships in the base packages, so a first install marks every migration
# as already applied; the user install has to register the host itself.
grep -q 'omarchy-install-chromium-theme' "$ROOT/install/user/chromium.sh" ||
  fail "user install runs the theme native messaging host setup"

fresh_home="$TMPDIR/fresh-install"
HOME="$fresh_home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
  bash -euo pipefail -c 'source "$ROOT/install/user/chromium.sh"'

[[ -f $fresh_home/.config/chromium/NativeMessagingHosts/com.omarchy.theme.json ]] ||
  fail "fresh install registers the theme native messaging host"
pass "fresh install registers the theme native messaging host"

# The host reads the active theme and frames it for the extension.
theme_home="$TMPDIR/theme-home"
current="$theme_home/.local/state/omarchy/current"
mkdir -p "$current/theme"
printf 'tokyo-night' >"$current/theme.name"
printf '[colors.primary]\nbackground = "#1a1b26"\n' >"$current/theme/alacritty.toml"
printf 'accent = "#7aa2f7"\n' >"$current/theme/colors.toml"

theme_json=$(HOME="$theme_home" XDG_RUNTIME_DIR="$TMPDIR/run" \
  bash -c 'source "$1"; build_state' bash "$ROOT/bin/omarchy-chromium-theme-host")
jq -e '.theme_name == "tokyo-night" and .bg == "#1a1b26" and .accent == "#7aa2f7"' <<<"$theme_json" >/dev/null ||
  fail "theme host reads the active Omarchy theme" "$theme_json"
pass "theme host reads the active Omarchy theme"

framed=$(XDG_RUNTIME_DIR="$TMPDIR/run" \
  bash -c 'source "$1"; emit "hi"' bash "$ROOT/bin/omarchy-chromium-theme-host" |
  od -An -v -tx1 | tr -d ' \n')
[[ $framed == "020000006869" ]] ||
  fail "theme host frames messages with a little-endian length prefix" "$framed"
pass "theme host frames messages with a little-endian length prefix"

# omarchy-theme-set calls the refresh to SIGUSR1 every running host; stale
# pidfiles are pruned.
run_dir="$TMPDIR/run/omarchy-theme"
mkdir -p "$run_dir"
echo 999999 >"$run_dir/999999.pid"

# A host can be killed before its EXIT trap removes the pidfile. If Linux later
# reuses that PID, the refresh must not send SIGUSR1 to the unrelated process.
echo "$$ 0" >"$run_dir/reused.pid"

marker="$TMPDIR/partial-pid-signalled"
MARKER="$marker" bash -c 'trap "touch \"$MARKER\"" USR1; while :; do sleep 1; done' &
partial_pid=$!
echo "$partial_pid" >"$run_dir/partial.pid"

# Drive the real host rather than a stand-in sleeper: a synthetic process with
# its own USR1 trap would keep this green even if the host's trap, its watchdog
# wait, or its second framed write regressed. Hold stdin open through a FIFO so
# the watchdog does not see EOF and exit.
host_out="$TMPDIR/host.out"
host_in="$TMPDIR/host.in"
mkfifo "$host_in"
: >"$host_out"
HOME="$theme_home" XDG_RUNTIME_DIR="$TMPDIR/run" \
  omarchy-chromium-theme-host <"$host_in" >"$host_out" 2>/dev/null &
host_pid=$!
# Keeping a writer attached is what holds the FIFO open.
sleep 300 >"$host_in" &
host_writer=$!

frame_count() {
  node - "$host_out" <<'JS'
const fs = require('fs')
const buf = fs.readFileSync(process.argv[2])
let at = 0
let frames = 0
while (at + 4 <= buf.length) {
  const len = buf.readUInt32LE(at)
  if (at + 4 + len > buf.length) break
  JSON.parse(buf.subarray(at + 4, at + 4 + len).toString('utf8'))
  frames++
  at += 4 + len
}
process.stdout.write(String(frames))
JS
}

# The host pushes once on connect, before it arms the watchdog.
for _ in $(seq 1 100); do [[ $(frame_count) -ge 1 ]] && break; sleep 0.05; done
[[ $(frame_count) -ge 1 ]] ||
  fail "theme host pushes the current theme on connect" "$(od -An -tx1 "$host_out" | head -2)"
[[ -s $run_dir/$host_pid.pid ]] ||
  fail "theme host writes its pidfile where the refresh looks" "$(ls "$run_dir")"
watchdog_pid=$(pgrep -P "$host_pid")
[[ -n $watchdog_pid && -z $(pgrep -P "$watchdog_pid") ]] ||
  fail "theme host watchdog does not spawn a child that can be orphaned"

XDG_RUNTIME_DIR="$TMPDIR/run" omarchy-chromium-theme-refresh

for _ in $(seq 1 100); do [[ $(frame_count) -ge 2 ]] && break; sleep 0.05; done
frames=$(frame_count)
# Read this before killing the host, which cleans its own pidfile up on exit.
kept_pidfile=$([[ -s $run_dir/$host_pid.pid ]] && echo yes || echo no)
kill "$host_pid" "$host_writer" 2>/dev/null
wait "$host_pid" 2>/dev/null
kill "$partial_pid" 2>/dev/null
wait "$partial_pid" 2>/dev/null

(( frames >= 2 )) ||
  fail "theme-set refresh makes the running host push again" "frames=$frames"

# The second frame has to be a usable theme, not just bytes on the pipe.
second=$(node - "$host_out" <<'JS'
const fs = require('fs')
const buf = fs.readFileSync(process.argv[2])
const out = []
let at = 0
while (at + 4 <= buf.length) {
  const len = buf.readUInt32LE(at)
  if (at + 4 + len > buf.length) break
  out.push(JSON.parse(buf.subarray(at + 4, at + 4 + len).toString('utf8')))
  at += 4 + len
}
process.stdout.write(JSON.stringify(out[1] || null))
JS
)
jq -e '.theme_name == "tokyo-night" and .bg == "#1a1b26"' <<<"$second" >/dev/null ||
  fail "theme host re-pushes a usable theme on refresh" "$second"
[[ ! -f $run_dir/999999.pid ]] || fail "theme-set refresh prunes stale pidfiles"
[[ ! -f $run_dir/reused.pid ]] || fail "theme-set refresh prunes reused pidfiles"
[[ ! -f $run_dir/partial.pid && ! -f $marker ]] ||
  fail "theme-set refresh rejects pidfiles without process start time"
# The refresh ran while the host was alive, so its own pidfile had to survive;
# the host removes it through its EXIT trap once we kill it above.
[[ $kept_pidfile == "yes" ]] || fail "theme-set refresh keeps live pidfiles" "$(ls "$run_dir")"
pass "theme-set refresh signals running hosts and prunes stale pidfiles"
