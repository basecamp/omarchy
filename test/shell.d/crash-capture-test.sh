#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
SYSTEMCTL_LOG="$TMPDIR/systemctl-log"

cat >"$TMPDIR/bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
SH

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/systemctl" "$TMPDIR/bin/omarchy-notification-send"

test_home="$TMPDIR/home"
flag="$test_home/.local/state/omarchy/toggles/crash-capture-off"

toggle_crash_capture() {
  PATH="$TMPDIR/bin:$ROOT/bin:$PATH" \
  SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
  HOME="$test_home" \
    "$ROOT/bin/omarchy-toggle-crash-capture"
}

toggle_crash_capture
[[ -f $flag ]] || fail "crash capture toggle disables the watcher"
grep -Fqx -- "--user stop omarchy-crash-watch.service" "$SYSTEMCTL_LOG" ||
  fail "crash capture toggle stops the running watcher, so disabling takes effect before the next login"
pass "crash capture toggle disables the watcher"

: >"$SYSTEMCTL_LOG"
toggle_crash_capture
[[ ! -f $flag ]] || fail "crash capture toggle re-enables the watcher"
grep -Fqx -- "--user start omarchy-crash-watch.service" "$SYSTEMCTL_LOG" ||
  fail "crash capture toggle starts the watcher, so enabling takes effect before the next login"
pass "crash capture toggle re-enables the watcher"

service="$ROOT/default/systemd/user/omarchy-crash-watch.service"
grep -Fx 'ConditionPathExists=!%h/.local/state/omarchy/toggles/crash-capture-off' "$service" >/dev/null ||
  fail "the watcher is pulled back in at every login, so disabling it never survives a logout"
pass "crash watcher stays disabled across logins"

grep -F 'omarchy-crash-watch.service' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null ||
  fail "crash capture is no longer on by default for new installs"
pass "crash capture is on by default"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = Object.fromEntries(items.map(item => [item.id, item]))

assertEqual(
  byId['trigger.toggle.crash-capture'].action,
  'omarchy-toggle-crash-capture',
  'menu toggles crash capture from Trigger > Toggle'
)
JS
