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

# Everything above drives one function at a time, which leaves the installer's
# own orchestration -- the loop over all three extensions, the registration
# Chrome reads, and the native host refresh -- resting on sudo and a Chrome
# binary the test machine may not have. Run the script itself against stubs for
# both so that work is covered wherever the suite runs.
stub_bin="$TMPDIR/stub-bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

# Chrome writes <dir>.crx beside the directory it packs. Standing in for the
# CRX3 container, the stub copies the manifest through, which keeps the key the
# extension was packed with readable below.
cat >"$stub_bin/google-chrome-stable" <<'STUB'
#!/bin/bash
set -euo pipefail

for arg in "$@"; do
  case $arg in
  --pack-extension=*) dir=${arg#*=} ;;
  --pack-extension-key=*) key=${arg#*=} ;;
  esac
done

[[ -s $key ]] || { echo "packed without a signing key" >&2; exit 1; }
cp "$dir/manifest.json" "$dir.crx"
STUB
chmod +x "$stub_bin/google-chrome-stable"

e2e_home="$TMPDIR/e2e"
e2e_state="$e2e_home/.local/state/omarchy/chrome-extensions"
e2e_external="$e2e_home/usr/share/google-chrome/extensions"

mkdir -p "$e2e_home/.config"
cat >"$e2e_home/.config/chrome-flags.conf" <<'CONF'
--ozone-platform=wayland
--load-extension=/usr/share/omarchy/default/chromium/extensions/copy-url
CONF

install_into_chrome() {
  HOME="$e2e_home" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_CHROME_EXTENSIONS_DIR="$e2e_external" \
    PATH="$stub_bin:$PATH" \
    omarchy-install-chrome-extensions
}

install_into_chrome

for name in "${EXTENSIONS[@]}"; do
  [[ -s $e2e_state/$name.crx ]] || fail "the installer packs a CRX for $name"
  [[ $(stat -c '%a' "$e2e_state/$name.pem") == "600" ]] ||
    fail "the installer keeps $name's signing key private" "$(stat -c '%a' "$e2e_state/$name.pem")"

  id=$(<"$e2e_state/$name.id")

  # The id Chrome derives from the CRX signature has to be the one the
  # registration is filed under, or Chrome installs nothing.
  packed_id=$(jq -r '.key' "$e2e_state/$name.crx" | base64 -d | extension_id)
  [[ $id == "$packed_id" ]] ||
    fail "$name is registered under the id Chrome derives from the CRX" "registered: $id, packed: $packed_id"

  jq -e --arg crx "$e2e_state/$name.crx" --arg version "$(extension_version "$name")" \
    '.external_crx == $crx and .external_version == $version' \
    "$e2e_external/$id.json" >/dev/null ||
    fail "Chrome's registration for $name points at the packed CRX and its manifest version"
done
pass "the installer packs, signs and registers every bundled extension for Chrome"

[[ $(ls "$e2e_external" | wc -l) == "3" ]] ||
  fail "the installer registers only the bundled extensions" "$(ls "$e2e_external")"
pass "the installer registers only the bundled extensions"

grep -q -- "--load-extension" "$e2e_home/.config/chrome-flags.conf" &&
  fail "the installer drops the switch Chrome refuses from the flags file"
grep -q -- "--ozone-platform=wayland" "$e2e_home/.config/chrome-flags.conf" ||
  fail "the installer keeps the switches Chrome honours in the flags file"
pass "the installer leaves the flags file with only the switches Chrome honours"

for host in com.omarchy.copy_url:copy-url com.omarchy.ytdlp:yt-dlp; do
  jq -e --arg origin "chrome-extension://$(<"$e2e_state/${host#*:}.id")/" \
    '.allowed_origins | index($origin)' \
    "$e2e_home/.config/google-chrome/NativeMessagingHosts/${host%%:*}.json" >/dev/null ||
    fail "the installer teaches ${host%%:*} the id Chrome minted"
done
pass "the installer teaches the native messaging hosts the ids Chrome minted"

# A second run must land on the same ids: minting fresh ones would leave Chrome
# with the old copy installed beside the new one.
before=$(cat "$e2e_state"/*.id)
install_into_chrome

[[ $before == "$(cat "$e2e_state"/*.id)" ]] ||
  fail "reinstalling keeps the ids Chrome already installed under"
[[ $(ls "$e2e_external" | wc -l) == "3" ]] ||
  fail "reinstalling leaves one registration per extension" "$(ls "$e2e_external")"
pass "reinstalling is idempotent"
