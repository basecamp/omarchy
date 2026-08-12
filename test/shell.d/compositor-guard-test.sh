#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command python3

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

runtime_dir="$test_dir/run"
stub_bin="$test_dir/bin"
mkdir -p "$runtime_dir" "$stub_bin"

# A bound AF_UNIX socket outlives the process that bound it, which is exactly the
# corpse a dead compositor leaves behind.
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$runtime_dir/wayland-1"

stub_hyprctl() {
  cat >"$stub_bin/hyprctl" <<STUB
#!/bin/bash
exit $1
STUB
  chmod +x "$stub_bin/hyprctl"
}

# The guard exits the shell it runs in, so run it in a child and report back what
# it did: the skip line, or the core limit it left behind for Quickshell.
run_guard() {
  env "$@" PATH="$stub_bin:$PATH" bash -c '
    source "$1/base-test.sh"
    ulimit -c unlimited 2>/dev/null || true
    require_compositor "sample runtime test"
    printf "launched with core limit %s\n" "$(ulimit -c)"
  ' bash "$SHELL_TEST_DIR" 2>&1 || printf 'guard exited %s\n' "$?"
}

skipped="ok - no Wayland compositor; skipping sample runtime test"

output=$(run_guard -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$runtime_dir")
[[ $output == "$skipped" ]] || fail "guard skips without a display" "$output"
pass "guard skips without a display"

# The sandbox shape from the bug report: the variable comes through, the runtime
# directory does not.
output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$test_dir/blocked")
[[ $output == "$skipped" ]] || fail "guard skips when the socket is unreachable" "$output"
pass "guard skips when the socket is unreachable"

stub_hyprctl 1
output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE=test)
[[ $output == "$skipped" ]] || fail "guard skips when the compositor stopped answering" "$output"
pass "guard skips when the compositor stopped answering"

# Without a signature there is nothing to ask, and a live socket is all the
# evidence there is: run rather than skip real coverage.
stub_hyprctl 1
output=$(run_guard -u HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir")
[[ $output == "launched with core limit 0" ]] || fail "guard runs when hyprctl cannot be asked" "$output"
pass "guard runs when hyprctl cannot be asked"

# Quickshell aborts if the compositor disappears mid-run, so the tests it is
# about to launch must not be able to dump core.
stub_hyprctl 0
output=$(run_guard WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR="$runtime_dir" HYPRLAND_INSTANCE_SIGNATURE=test)
[[ $output == "launched with core limit 0" ]] || fail "guard runs with core dumps disabled" "$output"
pass "guard runs with core dumps disabled"
