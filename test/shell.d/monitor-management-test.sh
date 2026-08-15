#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
command_log="$test_tmp/commands.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
printf 'clamshell continued\n' >>"$OMARCHY_TEST_COMMAND_LOG"
SH

cat >"$stub_bin/socat" <<'SH'
#!/bin/bash
printf 'watcher continued\n' >>"$OMARCHY_TEST_COMMAND_LOG"
SH

cat >"$stub_bin/omarchy-hw-external-monitors" <<'SH'
#!/bin/bash
exit 1
SH

chmod +x "$stub_bin"/*

HOME="$test_tmp/home" \
  PATH="$ROOT/bin:$PATH" \
  bash "$ROOT/migrations/1786813000.sh" >/dev/null

HOME="$test_tmp/home" PATH="$ROOT/bin:$PATH" omarchy-toggle-enabled monitor-management ||
  fail "monitor management was not enabled by default"

HOME="$test_tmp/home" \
  PATH="$ROOT/bin:$PATH" \
  omarchy-toggle monitor-management off

if HOME="$test_tmp/home" PATH="$ROOT/bin:$PATH" omarchy-toggle-enabled monitor-management; then
  fail "monitor management reported enabled after it was turned off"
fi

internal_toggle="$test_tmp/home/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua"
mkdir -p "$(dirname "$internal_toggle")"
touch "$internal_toggle"

HOME="$test_tmp/home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-hw-recover-internal-monitor"

[[ -e $internal_toggle ]] || fail "startup recovery changed monitor state while monitor management was disabled"

HOME="$test_tmp/home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  OMARCHY_TEST_COMMAND_LOG="$command_log" \
  "$ROOT/bin/omarchy-hyprland-monitor-clamshell"

HOME="$test_tmp/home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  XDG_RUNTIME_DIR="$test_tmp/run" \
  HYPRLAND_INSTANCE_SIGNATURE=test \
  OMARCHY_TEST_COMMAND_LOG="$command_log" \
  "$ROOT/bin/omarchy-hyprland-monitor-watch"

[[ ! -e $command_log ]] || fail "automatic monitor commands ran while monitor management was disabled"

HOME="$test_tmp/home" \
  PATH="$ROOT/bin:$PATH" \
  omarchy-toggle monitor-management on

[[ -e $test_tmp/home/.local/state/omarchy/toggles/monitor-management ]] || fail "monitor management remained disabled after turning it on"
HOME="$test_tmp/home" PATH="$ROOT/bin:$PATH" omarchy-toggle-enabled monitor-management ||
  fail "monitor management did not report enabled after it was turned on"

HOME="$test_tmp/home" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-hw-recover-internal-monitor"

[[ ! -e $internal_toggle ]] || fail "startup recovery did not resume after monitor management was enabled"
pass "external monitor managers can turn Omarchy's automatic monitor handling off and on"
