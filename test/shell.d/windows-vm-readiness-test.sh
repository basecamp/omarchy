#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

source "$ROOT/bin/omarchy-windows-vm" help >/dev/null 2>&1

assert_mounts_safe() { return 0; }
sleep() { return 0; }

container_status="stopped"
boot_after=2
rdp_after=2
events="$test_dir/events"
log_count="$test_dir/log-count"
rdp_count=0

dc() {
  [[ $* == "up -d" ]] || return 1
  printf '%s\n' "up" >>"$events"
  container_status="running"
}

docker() {
  if [[ $1 == "inspect" && $* == *".State.Status"* ]]; then
    printf '%s\n' "$container_status"
  elif [[ $1 == "inspect" && $* == *".State.StartedAt"* ]]; then
    printf '%s\n' "2026-09-01T00:00:00Z"
  elif [[ $1 == "logs" ]]; then
    local count=0
    [[ -f $log_count ]] && count=$(<"$log_count")
    ((++count))
    printf '%s\n' "$count" >"$log_count"
    printf '%s\n' "log" >>"$events"
    if ((count >= boot_after)); then
      printf '%s\n' "Windows started successfully"
    fi
  else
    return 1
  fi
}

rdp_port_ready() {
  ((++rdp_count))
  printf '%s\n' "rdp" >>"$events"
  ((rdp_count >= rdp_after))
}

__priv_up_wait || fail "readiness wait succeeds after the boot log and RDP listener are both ready"
[[ $(paste -sd, "$events") == "up,log,log,rdp,rdp" ]] || fail "RDP is not probed until the current boot reports success"
pass "readiness waits for RDP after the current boot reports success"

: >"$events"
printf '%s\n' 0 >"$log_count"
container_status="running"
boot_after=1
rdp_after=1
rdp_count=0
__priv_up_wait || fail "an already running VM with RDP ready is accepted"
[[ $(paste -sd, "$events") == "log,rdp" ]] || fail "an already running VM is not started again"
pass "an already running VM is checked without another compose up"

: >"$events"
printf '%s\n' 0 >"$log_count"
container_status="running"
boot_after=1
rdp_after=1000
rdp_count=0
if __priv_up_wait 2>"$test_dir/timeout-error"; then
  fail "a VM whose RDP listener never starts times out"
fi
grep -q "booted but RDP did not become reachable" "$test_dir/timeout-error" || fail "RDP timeout explains which readiness phase failed"
((rdp_count > 1)) || fail "RDP readiness is polled rather than checked once"
pass "RDP readiness timeout is bounded and diagnostic"
