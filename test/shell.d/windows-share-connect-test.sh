#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"
LOG="$TMPDIR/commands.log"

cat >"$TMPDIR/bin/gio" <<'SH'
#!/bin/bash
printf 'gio %s\n' "$*" >>"$COMMAND_LOG"
if [[ $1 == list ]]; then
  printf '%s\n' GLENN-PC PLAYON-DEV-NODE
  exit 0
fi
if [[ $1 == mount ]]; then
  cat >/dev/null
  printf '%s\n' "$2" >>"$MOUNTED_LOG"
  exit 0
fi
exit 0
SH

cat >"$TMPDIR/bin/smbclient" <<'SH'
#!/bin/bash
printf 'smbclient %s\n' "$*" >>"$COMMAND_LOG"
cat <<'OUT'
Sharename       Type      Comment
---------       ----      -------
Users           Disk
C$              Disk      Default share
IPC$            IPC       IPC Service
OUT
exit 0
SH

cat >"$TMPDIR/bin/gum" <<'SH'
#!/bin/bash
echo "gum should not run when host/user/password are provided" >&2
exit 1
SH

cat >"$TMPDIR/bin/omarchy-notification-send" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$TMPDIR/bin/timeout" <<'SH'
#!/bin/bash
shift
exec "$@"
SH

cat >"$TMPDIR/bin/nmblookup" <<'SH'
#!/bin/bash
exit 1
SH

chmod +x "$TMPDIR/bin"/*

run_connect() {
  PATH="$TMPDIR/bin:$PATH" \
    COMMAND_LOG="$LOG" \
    MOUNTED_LOG="$TMPDIR/mounted.log" \
    OMARCHY_SMB_USER=glenn \
    OMARCHY_SMB_PASSWORD=secret \
    "$ROOT/bin/omarchy-setup-windows-share" "$@"
}

: >"$LOG"
run_connect GLENN-PC
grep -Fq -- '-W GLENN-PC' "$LOG" || fail "domain is the Windows PC hostname, not WORKGROUP"
grep -Fq -- '-U glenn%secret' "$LOG" || fail "signs in as the Windows username"
grep -Fq -- 'smb://GLENN-PC/' "$TMPDIR/mounted.log" || fail "opens the PC so shared folders are listed"
! grep -Fq har0x "$LOG" || fail "does not use the Linux username"
pass "local admin username and password open the Windows PC"

run_node_test <<'JS'
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const byId = Object.fromEntries(items.map(item => [item.id, item]))

assertEqual(
  byId['trigger.windows-pc'].action,
  'omarchy-launch-floating-terminal-with-presentation omarchy-setup-windows-share',
  'menu signs in to a Windows PC from Trigger'
)
JS
