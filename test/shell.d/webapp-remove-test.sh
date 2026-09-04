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

# Removing any other web app must not touch the flags. The entry has to be back
# in the file first, or the assertion only re-reads the removal above.
cat >"$home/.config/chromium-flags.conf" <<EOF
--load-extension=$others,$slim
EOF
cat >"$home/.local/share/applications/Slack.desktop" <<EOF
[Desktop Entry]
Name=Slack
Exec=omarchy-launch-webapp https://slack.com/
Icon=slack
EOF
remove Slack
grep -q -- "--load-extension=$others,$slim$" "$home/.config/chromium-flags.conf" ||
  fail "removing another web app leaves the slim flags alone" \
    "$(cat "$home/.config/chromium-flags.conf")"
[[ ! -e $home/.local/share/applications/Slack.desktop ]] ||
  fail "the Slack launcher is removed"
pass "removing another web app does not touch the WhatsApp extension flags"

# The slim entry is last today only because its migration appended it, and the
# next extension migration to reuse that append leaves it first in the list.
cat >"$home/.local/share/applications/WhatsApp.desktop" <<EOF
[Desktop Entry]
Name=WhatsApp
Exec=omarchy-launch-webapp https://web.whatsapp.com/
Icon=whatsapp
EOF
cat >"$home/.config/brave-flags.conf" <<EOF
--load-extension=$slim,$others
EOF
remove WhatsApp
grep -q -- "--load-extension=$others$" "$home/.config/brave-flags.conf" ||
  fail "the slim entry is stripped when it leads the list" \
    "$(cat "$home/.config/brave-flags.conf")"
pass "the slim entry is stripped from either end of the list"

# An entry whose path merely starts with this one is a different extension, and
# the match has to end at a boundary to leave it its name.
cat >"$home/.local/share/applications/WhatsApp.desktop" <<EOF
[Desktop Entry]
Name=WhatsApp
Exec=omarchy-launch-webapp https://web.whatsapp.com/
Icon=whatsapp
EOF
cat >"$home/.config/brave-flags.conf" <<EOF
--load-extension=$others,$slim-backup
EOF
remove WhatsApp
grep -q -- "--load-extension=$others,$slim-backup$" "$home/.config/brave-flags.conf" ||
  fail "an extension named after this one keeps its own name" \
    "$(cat "$home/.config/brave-flags.conf")"
pass "only the slim entry itself is stripped"

# Remove -> Preinstalls runs omarchy-webapp-remove-all, which has its own
# loop and never called the single-command path: it must surface the same
# paired cleanup, or the "I want none of the web apps" route still leaves the
# extension behind (issue #9856).
cat >"$home/.local/share/applications/WhatsApp.desktop" <<EOF
[Desktop Entry]
Name=WhatsApp
Exec=omarchy-launch-webapp https://web.whatsapp.com/
Icon=whatsapp
EOF
cat >"$home/.config/chromium-flags.conf" <<EOF
--load-extension=$others,$slim
EOF
# remove-all delegates by bare command name, so the checkout has to lead PATH
# or the loop runs whatever omarchy-webapp-remove the machine has installed.
HOME="$home" OMARCHY_PATH="$opath" OMARCHY_REMOVE_NOTIFY=false PATH="$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-webapp-remove-all" "$home/.local/share/applications" >/dev/null
grep -q "whatsapp-slim" "$home/.config/chromium-flags.conf" &&
  fail "remove-all strips the slim flags too" "$(cat "$home/.config/chromium-flags.conf")"
grep -q -- "--load-extension=$others$" "$home/.config/chromium-flags.conf" ||
  fail "remove-all keeps the other extensions" "$(cat "$home/.config/chromium-flags.conf")"
[[ ! -e $home/.local/share/applications/WhatsApp.desktop ]] ||
  fail "remove-all removes the WhatsApp launcher"
pass "the remove-all path pairs the extension flags with the web apps"

pass "web app removal pairs the WhatsApp launcher with its slim extension"
