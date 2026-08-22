#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
STATE="$TMPDIR/show-hidden"

cat >"$TMPDIR/bin/gsettings" <<'SH'
#!/bin/bash
state_file=${GSETTINGS_STATE:?}
case "$1 $2 $3" in
  "get org.gnome.nautilus.preferences show-hidden-files")
    if [[ -f $state_file ]]; then
      cat "$state_file"
    else
      echo false
    fi
    ;;
  "set org.gnome.nautilus.preferences show-hidden-files")
    printf '%s\n' "$4" >"$state_file"
    ;;
  *)
    echo "unexpected gsettings: $*" >&2
    exit 1
    ;;
esac
SH

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/gsettings" "$TMPDIR/bin/omarchy-notification-send"

run_toggle() {
  PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
    GSETTINGS_STATE="$STATE" \
    "$ROOT/bin/omarchy-toggle-windows-admin-shares" "$@"
}

hidden_value() {
  PATH="$TMPDIR/bin:$PATH" GSETTINGS_STATE="$STATE" gsettings get org.gnome.nautilus.preferences show-hidden-files
}

[[ $(hidden_value) == false ]] || fail "admin shares start hidden"
run_toggle
[[ $(hidden_value) == true ]] || fail "toggle shows admin shares"
run_toggle off
[[ $(hidden_value) == false ]] || fail "off hides admin shares"
run_toggle on
[[ $(hidden_value) == true ]] || fail "on shows admin shares"
pass "windows admin shares toggle drives Files hidden-files setting"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = Object.fromEntries(items.map(item => [item.id, item]))

assertEqual(
  byId['trigger.toggle.windows-admin-shares'].action,
  'omarchy-toggle-windows-admin-shares',
  'menu toggles Windows admin shares from Trigger > Toggle'
)
JS
