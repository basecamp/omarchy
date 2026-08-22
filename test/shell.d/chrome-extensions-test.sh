#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""

export PATH="$ROOT/bin:$PATH"

cleanup() {
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_command jq
require_command openssl

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
extensions_dir="$ROOT/default/chromium/extensions"

source "$ROOT/bin/omarchy-install-chrome-extensions"

# Point the sourced installer at the sandbox instead of the real home.
OMARCHY_PATH="$ROOT"
STATE_DIR="$test_home/.local/state/omarchy/chrome-extensions"
FLAGS_FILE="$test_home/.config/chrome-flags.conf"
mkdir -p "$STATE_DIR" "$test_home/.config"

# The ids pinned in the native messaging manifests were derived from the public
# keys in the extension manifests, so they are known-good vectors for the same
# derivation Chrome applies to a CRX signing key.
pinned_id() {
  jq -r '.key' "$extensions_dir/$1/manifest.json" | base64 -d | extension_id
}

[[ $(pinned_id yt-dlp) == "dedjgknigfeelejglamclffonmophnfl" ]] ||
  fail "extension_id derives the yt-dlp id Chrome would compute" "$(pinned_id yt-dlp)"
[[ $(pinned_id copy-url) == "bgpiichlckmfanooecilcjemknkcpngb" ]] ||
  fail "extension_id derives the Copy URL id Chrome would compute" "$(pinned_id copy-url)"
pass "extension_id derives the ids Chrome computes from a public key"

key=$(signing_key yt-dlp)
[[ -s $key ]] || fail "signing_key mints a key on first use"
pass "signing_key mints a key on first use"

# Regenerating the key would mint a new id and orphan the installed extension.
before=$(sha256sum <"$key")
signing_key yt-dlp >/dev/null
[[ $before == $(sha256sum <"$key") ]] ||
  fail "signing_key reuses the existing key so Chrome's extension id stays put"
pass "signing_key reuses the existing key so Chrome's extension id stays put"

cat >"$FLAGS_FILE" <<'CONF'
--ozone-platform=wayland
--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url
CONF

drop_dead_load_extension_switch

grep -q -- "--load-extension" "$FLAGS_FILE" &&
  fail "the flags file drops the switch Chrome refuses"
grep -q -- "--ozone-platform=wayland" "$FLAGS_FILE" ||
  fail "the flags file keeps the switches Chrome honours"
pass "the flags file drops the switch Chrome refuses"

# The native messaging hosts allow one origin per extension id, and Chrome's
# copies carry the locally minted id rather than the pinned one.
echo "abcdefghijklmnopabcdefghijklmnop" >"$STATE_DIR/yt-dlp.id"
echo "ponmlkjihgfedcbaponmlkjihgfedcba" >"$STATE_DIR/copy-url.id"

HOME="$test_home" OMARCHY_PATH="$ROOT" omarchy-install-chromium-ytdlp
HOME="$test_home" OMARCHY_PATH="$ROOT" omarchy-install-chromium-copy-url

jq -e '.allowed_origins == [
  "chrome-extension://dedjgknigfeelejglamclffonmophnfl/",
  "chrome-extension://abcdefghijklmnopabcdefghijklmnop/"
]' "$test_home/.config/google-chrome/NativeMessagingHosts/com.omarchy.ytdlp.json" >/dev/null ||
  fail "yt-dlp native host allows both the Chromium and Chrome extension ids"
pass "yt-dlp native host allows both the Chromium and Chrome extension ids"

jq -e '.allowed_origins == [
  "chrome-extension://bgpiichlckmfanooecilcjemknkcpngb/",
  "chrome-extension://ponmlkjihgfedcbaponmlkjihgfedcba/"
]' "$test_home/.config/google-chrome/NativeMessagingHosts/com.omarchy.copy_url.json" >/dev/null ||
  fail "Copy URL native host allows both the Chromium and Chrome extension ids"
pass "Copy URL native host allows both the Chromium and Chrome extension ids"

# Without Chrome the hosts must keep the pinned id and nothing else.
bare_home="$TMPDIR/bare"
HOME="$bare_home" OMARCHY_PATH="$ROOT" omarchy-install-chromium-ytdlp

jq -e '.allowed_origins == ["chrome-extension://dedjgknigfeelejglamclffonmophnfl/"]' \
  "$bare_home/.config/chromium/NativeMessagingHosts/com.omarchy.ytdlp.json" >/dev/null ||
  fail "yt-dlp native host keeps only the pinned id when Chrome is absent"
pass "yt-dlp native host keeps only the pinned id when Chrome is absent"

echo "bcklgckdehleclkgblfhfpocdgaikemg" >"$STATE_DIR/whatsapp-slim.id"

# Chrome only reinstalls a CRX when external_version outruns what it has.
for name in "${EXTENSIONS[@]}"; do
  jq -e --arg crx "$STATE_DIR/$name.crx" --arg version "$(extension_version "$name")" \
    '.external_crx == $crx and .external_version == $version' \
    <(external_pref "$name") >/dev/null ||
    fail "the external pref points Chrome at the packed $name CRX and its manifest version"
done
pass "the external pref points Chrome at each packed CRX and its manifest version"

if command -v google-chrome-stable >/dev/null; then
  pack_extension yt-dlp "$key"

  [[ -s $STATE_DIR/yt-dlp.crx ]] || fail "pack_extension writes a CRX for Chrome to install"
  pass "pack_extension writes a CRX for Chrome to install"
else
  pass "Google Chrome not installed; skipping CRX packing"
fi
