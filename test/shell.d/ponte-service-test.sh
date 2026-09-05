#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$tmp_dir/bin"

cat >"$tmp_dir/bin/omarchy-pkg-add" <<'SCRIPT'
#!/bin/bash
printf 'add:%s\n' "$*" >>"$PONTE_TEST_LOG"
exit "${PONTE_TEST_ADD_STATUS:-0}"
SCRIPT

cat >"$tmp_dir/bin/omarchy-pkg-present" <<'SCRIPT'
#!/bin/bash
printf 'present:%s\n' "$*" >>"$PONTE_TEST_LOG"
exit "${PONTE_TEST_PRESENT_STATUS:-0}"
SCRIPT

cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'SCRIPT'
#!/bin/bash
printf 'drop:%s\n' "$*" >>"$PONTE_TEST_LOG"
exit "${PONTE_TEST_DROP_STATUS:-0}"
SCRIPT

cat >"$tmp_dir/bin/ponte" <<'SCRIPT'
#!/bin/bash
printf 'ponte:%s\n' "$*" >>"$PONTE_TEST_LOG"
exit "${PONTE_TEST_UNINSTALL_STATUS:-0}"
SCRIPT

for command in systemctl tailscale sudo curl ydotool ydotoold; do
  cat >"$tmp_dir/bin/$command" <<'SCRIPT'
#!/bin/bash
printf 'unexpected:%s:%s\n' "${0##*/}" "$*" >>"$PONTE_TEST_LOG"
exit 91
SCRIPT
done
chmod +x "$tmp_dir/bin/"*
export PONTE_TEST_LOG="$tmp_dir/log"
export PATH="$tmp_dir/bin:$PATH"

"$ROOT/bin/omarchy-install-service-ponte" >"$tmp_dir/output"
[[ $(cat "$PONTE_TEST_LOG") == 'add:ponte-remote' ]] || fail "Ponte package install never configures or starts services"
pass "Ponte package install never configures or starts services"
grep -q 'ponte setup' "$tmp_dir/output" && grep -q 'ponte install' "$tmp_dir/output" || fail "Ponte setup and activation are explicit next steps"
pass "Ponte setup and activation are explicit next steps"

: >"$PONTE_TEST_LOG"
status=0
PONTE_TEST_ADD_STATUS=17 "$ROOT/bin/omarchy-install-service-ponte" >"$tmp_dir/output" 2>&1 || status=$?
[[ $status == 17 && ! -s $tmp_dir/output ]] || fail "Ponte package failure propagates without a success message"
[[ $(cat "$PONTE_TEST_LOG") == 'add:ponte-remote' ]] || fail "Ponte package failure has no follow-up actions"
pass "Ponte package failure propagates without follow-up actions or success"

: >"$PONTE_TEST_LOG"
"$ROOT/bin/omarchy-remove-service-ponte"
[[ $(cat "$PONTE_TEST_LOG") == $'present:ponte-remote\nponte:uninstall\ndrop:ponte-remote' ]] || fail "Ponte stops and removes its user units before dropping the package"
pass "Ponte stops and removes its user units before dropping the package"

: >"$PONTE_TEST_LOG"
status=0
PONTE_TEST_UNINSTALL_STATUS=23 "$ROOT/bin/omarchy-remove-service-ponte" || status=$?
[[ $status == 23 && $(cat "$PONTE_TEST_LOG") == $'present:ponte-remote\nponte:uninstall' ]] || fail "Ponte teardown failure keeps the package available for recovery"
pass "Ponte teardown failure keeps the package available for recovery"

: >"$PONTE_TEST_LOG"
PONTE_TEST_PRESENT_STATUS=1 "$ROOT/bin/omarchy-remove-service-ponte"
[[ $(cat "$PONTE_TEST_LOG") == 'present:ponte-remote' ]] || fail "Ponte package absence leaves source installs alone"
pass "Ponte package absence leaves source installs alone"

: >"$PONTE_TEST_LOG"
status=0
PONTE_TEST_DROP_STATUS=29 "$ROOT/bin/omarchy-remove-service-ponte" || status=$?
[[ $status == 29 ]] || fail "Ponte package removal failure propagates"
pass "Ponte package removal failure propagates"
