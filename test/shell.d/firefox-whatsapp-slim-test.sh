#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

EXT_DIR="$ROOT/default/firefox/extensions/whatsapp-slim"

# The Firefox/Zen port keeps the same content scripts as the Chromium version
jq -e '
  .content_scripts[0].css == ["whatsapp.css"] and
  .content_scripts[0].js == ["system-theme.js"] and
  .content_scripts[0].run_at == "document_start"
' "$EXT_DIR/manifest.json" >/dev/null || fail "Firefox WhatsApp Slim keeps the Chromium content scripts"
pass "Firefox WhatsApp Slim keeps the Chromium content scripts"

# It must be a Firefox WebExtension with a stable id, and no Chromium key
jq -e '
  .manifest_version == 3 and
  (.browser_specific_settings.gecko.id == "whatsapp-slim@omarchy.org") and
  (has("key") | not)
' "$EXT_DIR/manifest.json" >/dev/null || fail "Firefox WhatsApp Slim has a gecko id and no Chromium key"
pass "Firefox WhatsApp Slim has a gecko id and no Chromium key"

# The shared CSS/JS files are identical to the Chromium originals
for f in whatsapp.css system-theme.js; do
  cmp -s "$ROOT/default/firefox/extensions/whatsapp-slim/$f" \
        "$ROOT/default/chromium/extensions/whatsapp-slim/$f" \
    || fail "$f is identical to the Chromium version"
  pass "$f is identical to the Chromium version"
done
