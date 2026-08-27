#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

EXT_DIR="$ROOT/default/firefox/extensions/whatsapp-slim"

# The Firefox/Zen port keeps the same CSS as the Chromium version
cmp -s "$EXT_DIR/whatsapp.css" "$ROOT/default/chromium/extensions/whatsapp-slim/whatsapp.css" \
  || fail "Firefox WhatsApp Slim keeps the Chromium whatsapp.css"
pass "Firefox WhatsApp Slim keeps the Chromium whatsapp.css"

cmp -s "$EXT_DIR/system-theme.js" "$ROOT/default/chromium/extensions/whatsapp-slim/system-theme.js" \
  || fail "Firefox WhatsApp Slim keeps the Chromium system-theme.js"
pass "Firefox WhatsApp Slim keeps the Chromium system-theme.js"

# The manifest is a Firefox WebExtension: gecko id, no Chromium key
jq -e '
  .manifest_version == 3 and
  (.browser_specific_settings.gecko.id == "whatsapp-slim@omarchy.org") and
  (has("key") | not)
' "$EXT_DIR/manifest.json" >/dev/null || fail "Firefox WhatsApp Slim has a gecko id and no Chromium key"
pass "Firefox WhatsApp Slim has a gecko id and no Chromium key"

# The installer must wrap the CSS in a @-moz-document rule for userContent.css
installer="$ROOT/bin/omarchy-webapp-zen-install"
grep -q 'url-prefix("https://web.whatsapp.com/")' "$installer" \
  || fail "zen-install wraps WhatsApp Slim CSS in @-moz-document"
pass "zen-install wraps WhatsApp Slim CSS in @-moz-document"
