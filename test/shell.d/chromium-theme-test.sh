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

theme_json=$(HOME="$theme_home" bash -c 'source "$1"; build_state' bash "$ROOT/bin/omarchy-chromium-theme-host")
jq -e '.theme_name == "tokyo-night" and .bg == "#1a1b26" and .accent == "#7aa2f7"' <<<"$theme_json" >/dev/null ||
  fail "theme host reads the active Omarchy theme" "$theme_json"
pass "theme host reads the active Omarchy theme"

framed=$(bash -c 'source "$1"; emit "hi"' bash "$ROOT/bin/omarchy-chromium-theme-host" | od -An -v -tx1 | tr -d ' \n')
[[ $framed == "020000006869" ]] ||
  fail "theme host frames messages with a little-endian length prefix" "$framed"
pass "theme host frames messages with a little-endian length prefix"

# omarchy-theme-set calls the refresh to SIGUSR1 every running host; stale
# pidfiles are pruned.
run_dir="$TMPDIR/run/omarchy-theme"
mkdir -p "$run_dir"
echo 999999 >"$run_dir/999999.pid"

marker="$TMPDIR/usr1-received"
# `sleep & wait` (not a foreground sleep) so USR1 interrupts promptly — the same
# interruptible-sleep reason the real host waits on its watchdog.
MARKER="$marker" bash -c 'trap "touch \"$MARKER\"; exit 0" USR1; echo $$ >"$1"; sleep 30 & wait' \
  bash "$run_dir/live.pid" &
sleeper=$!
for _ in $(seq 1 40); do [[ -s $run_dir/live.pid ]] && break; sleep 0.05; done

XDG_RUNTIME_DIR="$TMPDIR/run" omarchy-chromium-theme-refresh

for _ in $(seq 1 40); do [[ -f $marker ]] && break; sleep 0.05; done
kill "$sleeper" 2>/dev/null
[[ -f $marker ]] || fail "theme-set refresh signals a running host"
[[ ! -f $run_dir/999999.pid ]] || fail "theme-set refresh prunes stale pidfiles"
[[ -f $run_dir/live.pid ]] || fail "theme-set refresh keeps live pidfiles"
pass "theme-set refresh signals running hosts and prunes stale pidfiles"
