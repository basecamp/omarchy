#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

export HOME="$test_tmp/home"
mkdir -p "$HOME"

"$ROOT/bin/omarchy-webapp-install" \
  "Normal Web App" \
  "https://example.com/products?tab=featured#details" \
  "normal-icon"

normal_desktop="$HOME/.local/share/applications/Normal Web App.desktop"
normal_exec=$(grep '^Exec=' "$normal_desktop")
[[ $normal_exec == "Exec=omarchy-launch-webapp https://example.com/products?tab=featured#details" ]] ||
  fail "normal web apps keep the URL launcher" "$normal_exec"
pass "normal web apps keep the URL launcher"

"$ROOT/bin/omarchy-webapp-install" \
  "Custom Web App" \
  "HTTPS://Example.COM:8443/path/to/app?mode=full#meeting" \
  "custom-icon" \
  "custom-webapp-handler --profile work %u" \
  "x-scheme-handler/custom;x-scheme-handler/custom-secure;"

custom_desktop="$HOME/.local/share/applications/Custom Web App.desktop"
custom_exec=$(grep '^Exec=' "$custom_desktop")
[[ $custom_exec == "Exec=env OMARCHY_WEBAPP_ORIGIN=https://example.com:8443 custom-webapp-handler --profile work %u" ]] ||
  fail "custom web apps preserve their canonical origin and command arguments" "$custom_exec"
pass "custom web apps preserve their canonical origin and command arguments"

custom_mime=$(grep '^MimeType=' "$custom_desktop")
[[ $custom_mime == "MimeType=x-scheme-handler/custom;x-scheme-handler/custom-secure;" ]] ||
  fail "custom web apps preserve MIME types" "$custom_mime"
pass "custom web apps preserve MIME types"

"$ROOT/bin/omarchy-webapp-install" "Custom Protocol" "zoommtg://join" "custom-icon" "custom-handler %u"
protocol_exec=$(grep '^Exec=' "$HOME/.local/share/applications/Custom Protocol.desktop")
[[ $protocol_exec == "Exec=custom-handler %u" ]] ||
  fail "custom protocols keep their handler without web origin metadata" "$protocol_exec"
pass "custom protocols keep their handler without web origin metadata"

hey_exec=$(grep '^Exec=' "$ROOT/applications/HEY.desktop")
[[ $hey_exec == "Exec=env OMARCHY_WEBAPP_ORIGIN=https://app.hey.com omarchy-webapp-handler-hey %u" ]] ||
  fail "bundled HEY launcher preserves its origin" "$hey_exec"
pass "bundled HEY launcher preserves its origin"

zoom_exec=$(grep '^Exec=' "$ROOT/applications/Zoom.desktop")
[[ $zoom_exec == "Exec=env OMARCHY_WEBAPP_ORIGIN=https://app.zoom.us omarchy-webapp-handler-zoom %u" ]] ||
  fail "bundled Zoom launcher preserves its origin" "$zoom_exec"
pass "bundled Zoom launcher preserves its origin"
