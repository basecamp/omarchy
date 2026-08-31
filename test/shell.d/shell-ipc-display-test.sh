#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/run"
touch "$test_dir/run/wayland-1" "$test_dir/run/wayland-1.lock"

cat >"$test_dir/bin/qs" <<'STUB'
#!/bin/bash
printf 'display=[%s] args=[%s]\n' "$WAYLAND_DISPLAY" "$*"
STUB
chmod +x "$test_dir/bin/qs"

export PATH="$test_dir/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$test_dir/run"

# Callers from a stripped environment have no WAYLAND_DISPLAY, and qs matches
# instances by display.
output=$(env -u WAYLAND_DISPLAY "$ROOT/bin/omarchy-shell" omarchy.indicators refresh)
[[ $output == "display=[wayland-1] args=[ipc -n --any-display -p $ROOT/shell call -- omarchy.indicators refresh]" ]] || fail "shell ipc recovers a missing display" "$output"
pass "shell ipc recovers a missing display"

output=$(WAYLAND_DISPLAY=wayland-9 "$ROOT/bin/omarchy-shell" omarchy.indicators refresh)
[[ $output == "display=[wayland-9] args=[ipc -n --any-display -p $ROOT/shell call -- omarchy.indicators refresh]" ]] || fail "shell ipc keeps an existing display" "$output"
pass "shell ipc keeps an existing display"

grep -Fq 'qs ipc -n --any-display' "$ROOT/bin/omarchy-shell" || fail "shell IPC remains tied to a caller sandbox's display"
pass "shell ipc reaches the configured Shell across display namespaces"
