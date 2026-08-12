#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

windows_vm_command="$ROOT/bin/omarchy-windows-vm"

rg -q '^    restart: "no"$' "$windows_vm_command" ||
  fail "Windows VM uses manual startup by default"
pass "Windows VM uses manual startup by default"

if rg -q '^    restart: unless-stopped$' "$windows_vm_command"; then
  fail "Windows VM does not restart automatically at boot"
fi
pass "Windows VM does not restart automatically at boot"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

test_home="$test_tmp/home"
fake_bin="$test_tmp/bin"
mkdir -p "$test_home/.config/windows" "$fake_bin"

cat >"$test_home/.config/windows/docker-compose.yml" <<'YAML'
services:
  windows:
    environment:
      USERNAME: "docker"
      PASSWORD: "admin"
YAML

cat >"$fake_bin/docker" <<'STUB'
#!/bin/bash
[[ $1 == "inspect" ]] && echo running
STUB

cat >"$fake_bin/docker-compose" <<'STUB'
#!/bin/bash
printf 'docker-compose %s\n' "$*" >>"$TEST_LOG"
STUB

cat >"$fake_bin/gum" <<'STUB'
#!/bin/bash
:
STUB

cat >"$fake_bin/hyprctl" <<'STUB'
#!/bin/bash
echo '[{"focused":true,"scale":1}]'
STUB

cat >"$fake_bin/xfreerdp3" <<'STUB'
#!/bin/bash
exit "${RDP_STATUS:-0}"
STUB

chmod +x "$fake_bin"/*

set +e
output=$(
  HOME="$test_home" TEST_LOG="$test_tmp/calls.log" RDP_STATUS=1 \
    PATH="$fake_bin:$PATH" bash "$windows_vm_command" launch 2>&1
)
status=$?
set -e

(( status == 1 )) || fail "Windows VM launch returns the RDP failure" "got status $status"
[[ ! -e $test_tmp/calls.log ]] ||
  fail "Windows VM stays running when RDP fails" "$(cat "$test_tmp/calls.log")"
grep -qF 'RDP connection failed. Windows VM is still running.' <<<"$output" ||
  fail "Windows VM explains how to reconnect after RDP fails" "$output"
pass "Windows VM survives a failed RDP connection"

HOME="$test_home" TEST_LOG="$test_tmp/calls.log" RDP_STATUS=0 \
  PATH="$fake_bin:$PATH" bash "$windows_vm_command" launch >/dev/null

grep -qFx "docker-compose -f $test_home/.config/windows/docker-compose.yml down" "$test_tmp/calls.log" ||
  fail "Windows VM still stops after a successful RDP session" "$(cat "$test_tmp/calls.log")"
pass "Windows VM keeps its automatic stop after a successful RDP session"
