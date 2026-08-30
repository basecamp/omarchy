#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/home/.config/1Password"

for browser_dir in \
  chromium/NativeMessagingHosts \
  google-chrome/Profile\ 1/NativeMessagingHosts \
  BraveSoftware/Brave-Browser/NativeMessagingHosts \
  microsoft-edge/NativeMessagingHosts \
  vivaldi/NativeMessagingHosts; do
  mkdir -p "$tmp_dir/home/.config/$browser_dir"
  touch "$tmp_dir/home/.config/$browser_dir/com.1password.1password.json"
done

mkdir -p "$tmp_dir/home/.config/not-a-browser"
touch "$tmp_dir/home/.config/not-a-browser/com.1password.1password.json"
touch "$tmp_dir/home/.config/1Password/settings.json"

cat >"$tmp_dir/bin/sudo" <<'SCRIPT'
#!/bin/bash
if [[ $1 == rm ]]; then
  exit 0
fi
exec "$@"
SCRIPT

cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf '%s\n' "$*" >"$OMARCHY_TEST_LOG"
SCRIPT

chmod +x "$tmp_dir/bin/sudo" "$tmp_dir/bin/omarchy-pkg-drop"

OMARCHY_TEST_LOG="$tmp_dir/pkg-drop.log" HOME="$tmp_dir/home" PATH="$tmp_dir/bin:$PATH" \
  bash "$ROOT/bin/omarchy-remove-service-1password"

for browser_dir in \
  chromium/NativeMessagingHosts \
  google-chrome/Profile\ 1/NativeMessagingHosts \
  BraveSoftware/Brave-Browser/NativeMessagingHosts \
  microsoft-edge/NativeMessagingHosts \
  vivaldi/NativeMessagingHosts; do
  [[ ! -e "$tmp_dir/home/.config/$browser_dir/com.1password.1password.json" ]] ||
    fail "1Password removal deletes stale native-messaging manifests" "$browser_dir"
done
pass "1Password removal deletes stale native-messaging manifests"

[[ -e "$tmp_dir/home/.config/not-a-browser/com.1password.1password.json" ]] ||
  fail "1Password removal leaves unrelated configuration files alone"
[[ -e "$tmp_dir/home/.config/1Password/settings.json" ]] ||
  fail "1Password removal preserves the user's 1Password data"
pass "1Password removal leaves unrelated configuration files alone"

grep -Fxq '1password 1password-cli' "$tmp_dir/pkg-drop.log" ||
  fail "1Password removal drops both packages"
pass "1Password removal drops both packages"
