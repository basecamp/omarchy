#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

home="$tmp_dir/home"
opath="$tmp_dir/omarchy"
mkdir -p "$home/.local/share/applications" \
  "$home/.local/share/icons/hicolor/256x256/apps" \
  "$home/.local/share/applications/icons" "$home/.config" "$opath"

slim="$opath/default/chromium/extensions/whatsapp-slim"
others="/usr/share/omarchy/default/chromium/extensions/copy-url"

# A WhatsApp launcher, as omarchy-webapp-install writes it.
cat >"$home/.local/share/applications/WhatsApp.desktop" <<EOF
[Desktop Entry]
Name=WhatsApp
Exec=omarchy-launch-webapp https://web.whatsapp.com/
Icon=whatsapp
EOF

# The flags state from the two migrations: append to an existing list
# (chromium) and a sole extension line (brave-origin).
cat >"$home/.config/chromium-flags.conf" <<EOF
--load-extension=$others,$slim
EOF
cat >"$home/.config/brave-origin-flags.conf" <<EOF
--load-extension=$slim
EOF
cat >"$home/.config/google-chrome-flags.conf" <<EOF
--flag-without-whatsapp
EOF

remove() {
  HOME="$home" OMARCHY_PATH="$opath" OMARCHY_REMOVE_NOTIFY=false \
    "$ROOT/bin/omarchy-webapp-remove" "$1"
}

remove WhatsApp

grep -q "whatsapp-slim" "$home/.config/chromium-flags.conf" &&
  fail "removing WhatsApp strips the slim flag from chromium-flags.conf" \
    "$(cat "$home/.config/chromium-flags.conf")"
grep -q -- "--load-extension=$others$" "$home/.config/chromium-flags.conf" ||
  fail "the other extensions in chromium-flags.conf are kept" \
    "$(cat "$home/.config/chromium-flags.conf")"
grep -q "whatsapp-slim" "$home/.config/brave-origin-flags.conf" &&
  fail "removing WhatsApp drops the slim flag from brave-origin-flags.conf" \
    "$(cat "$home/.config/brave-origin-flags.conf")"
grep -q "whatsapp-slim" "$home/.config/google-chrome-flags.conf" &&
  fail "unrelated flags files are not modified"
[[ ! -e $home/.local/share/applications/WhatsApp.desktop ]] ||
  fail "the WhatsApp launcher is removed"
pass "removing WhatsApp removes the launcher and the slim extension flags"

# Removing any other web app must not touch the flags.
cat >"$home/.local/share/applications/Slack.desktop" <<EOF
[Desktop Entry]
Name=Slack
Exec=omarchy-launch-webapp https://slack.com/
Icon=slack
EOF
remove Slack
grep -q "whatsapp-slim" "$home/.config/chromium-flags.conf" &&
  fail "removing another web app leaves the slim flags alone"
[[ ! -e $home/.local/share/applications/Slack.desktop ]] ||
  fail "the Slack launcher is removed"
pass "removing another web app does not touch the WhatsApp extension flags"

pass "web app removal pairs the WhatsApp launcher with its slim extension"
