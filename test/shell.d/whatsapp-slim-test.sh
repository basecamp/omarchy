#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq
require_command node

EXT_DIR="$ROOT/default/chromium/extensions/whatsapp-slim"

jq -e '
  .content_scripts[0].js == ["system-theme.js"] and
  .content_scripts[0].run_at == "document_start"
' "$EXT_DIR/manifest.json" >/dev/null || fail "WhatsApp enables system theming before startup"

mode=$(node - "$EXT_DIR/system-theme.js" <<'JS'
const fs = require("fs")
const values = new Map()
let reloaded = false
global.localStorage = {
  getItem: key => values.get(key),
  setItem: (key, value) => values.set(key, value),
}
global.location = { reload: () => { reloaded = true } }
eval(fs.readFileSync(process.argv[2], "utf8"))
process.stdout.write(`${values.get("system-theme-mode")}:${reloaded}`)
JS
)

[[ $mode == "true:true" ]] || fail "WhatsApp selects its system theme mode" "$mode"
pass "WhatsApp follows the system theme through its existing slim extension"
