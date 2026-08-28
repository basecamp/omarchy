#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

proof_pid=""
cleanup() {
  if [[ -n $proof_pid ]] && kill -0 "$proof_pid" 2>/dev/null; then
    kill "$proof_pid" 2>/dev/null || true
    wait "$proof_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

host=/usr/bin/omarchy-plugin-host
worker=/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker
module=/usr/lib/qt6/qml/Omarchy/PluginHost

[[ -x $host ]] || fail "secure plugin host is installed"
[[ -x $worker ]] || fail "secure plugin worker is installed privately"
[[ ! -e /usr/bin/omarchy-plugin-qml-worker ]] || fail "secure plugin worker is absent from PATH"
[[ -r $module/qmldir && -r $module/libomarchy-plugin-host-bridge.so ]] ||
  fail "secure plugin bridge module is installed"
[[ -r /usr/lib/systemd/user/omarchy-plugin-host.service ]] ||
  fail "secure plugin user service is installed"
pass "secure plugin package artifacts are installed"

"$host" --version | grep -Eq '^omarchy-plugin-host [^ ]+ envelope=1$' ||
  fail "secure plugin host reports its protocol version"
"$host" --check-launch-prerequisites >/dev/null ||
  fail "secure plugin launch prerequisites are available"
pass "secure plugin host prerequisites are available"

set +e
"$worker" >/dev/null 2>&1
worker_status=$?
set -e
(( worker_status == 78 )) ||
  fail "direct secure plugin worker launch is denied" "exit status was $worker_status"
pass "direct secure plugin worker launch is denied"

systemctl --user is-enabled --quiet omarchy-plugin-host.service ||
  fail "secure plugin host service is enabled"
systemctl --user is-active --quiet omarchy-plugin-host.service ||
  fail "secure plugin host service is active"
pass "secure plugin host service is enabled and active"

/usr/lib/qt6/bin/qml "$ROOT/test/acceptance.d/fixtures/plugin-host-module.qml" \
  >"$ARTIFACTS/plugin-host-module.log" 2>&1 &
proof_pid=$!

wait_until "secure plugin bridge appears in the graphical session" 20 \
  screen_contains "SECURE PLUGIN BRIDGE"
screenshot "success-secure-plugin-bridge-module"

kill "$proof_pid" 2>/dev/null || true
wait "$proof_pid" 2>/dev/null || true
proof_pid=""
pass "secure plugin bridge module loads with packaged Qt under Wayland"
