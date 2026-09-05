#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command node

EXT_DIR="$ROOT/default/chromium/extensions/youtube-tile"

# A keyless unpacked extension gets a path-derived id, so its settings would go
# stale if its load path or packaging ever changed. The pinned key keeps the id
# stable everywhere.
youtube_tile_id=$(node - <<'JS' "$EXT_DIR/manifest.json"
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

[[ $youtube_tile_id == "leljffmfchpbnepfomgboahabahpmmcj" ]] ||
  fail "youtube-tile extension manifest has the stable id" "$youtube_tile_id"
pass "youtube-tile extension manifest has the stable id"

# The extension only reaches a browser through the shared flags file, and a new
# entry there is invisible to existing installs without a migration. Both have
# been forgotten before, so both are asserted.
grep -q "extensions/youtube-tile" "$ROOT/config/chromium-flags.conf" ||
  fail "youtube-tile is loaded from the default Chromium flags"
pass "youtube-tile is loaded from the default Chromium flags"

if ! grep -rlq "extensions/youtube-tile" "$ROOT/migrations"; then
  fail "a migration adds youtube-tile to existing browser flag files"
fi
pass "a migration adds youtube-tile to existing browser flag files"

# Tile mode is a layout fix, not a theme. The palette pipeline lives in the
# standalone extension and cannot work from a root-owned $OMARCHY_PATH, so a
# stray --omy-* reference here means theming leaked back in.
if matches=$(grep -rn -- "--omy-" "$EXT_DIR" 2>/dev/null); then
  fail "youtube-tile carries no palette variables" "$matches"
fi
pass "youtube-tile carries no palette variables"

node --check "$EXT_DIR/content.js" || fail "youtube-tile content script parses"
pass "youtube-tile content script parses"
