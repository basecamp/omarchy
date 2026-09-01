#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

desktop="$ROOT/default/wayland-sessions/omarchy.desktop"
starter="$ROOT/bin/omarchy-hyprland-session-start"

grep -Fx 'Exec=/usr/bin/omarchy-hyprland-session-start' "$desktop" >/dev/null ||
  fail "session desktop starts through omarchy-hyprland-session-start"
grep -F 'uwsm start -g -1' "$desktop" >/dev/null &&
  fail "session desktop must not call uwsm -g -1 (races the SDDM greeter)"
pass "session desktop uses the uwsm session wrapper"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/uwsm" <<'BASH'
#!/bin/bash
printf 'UWSM:%s\n' "$*" >"${FAKE_LOG_DIR}/uwsm"
exit 0
BASH

cat >"$fake_bin/systemctl" <<'BASH'
#!/bin/bash
printf 'SYSTEMCTL:%s\n' "$*" >>"${FAKE_LOG_DIR}/systemctl"

if [[ $1 == --user && $2 == is-active && $4 == graphical-session.target ]]; then
  if [[ ${FAKE_GRAPHICAL_ACTIVE:-0} == 1 ]]; then
    exit 0
  fi
  exit 3
fi

exit 0
BASH

cat >"$fake_bin/pgrep" <<'BASH'
#!/bin/bash
if [[ ${FAKE_COMPOSITOR_RUNNING:-0} == 1 ]]; then
  exit 0
fi
exit 1
BASH

chmod 0755 "$fake_bin/uwsm" "$fake_bin/systemctl" "$fake_bin/pgrep"

run_starter() {
  FAKE_LOG_DIR="$test_tmp" PATH="$fake_bin:$PATH" "$starter"
}

: >"$test_tmp/systemctl"
FAKE_GRAPHICAL_ACTIVE=0 FAKE_COMPOSITOR_RUNNING=0 run_starter
grep -Fx 'UWSM:start -e -D Hyprland hyprland.desktop' "$test_tmp/uwsm" >/dev/null ||
  fail "wrapper execs uwsm without -g when graphical-session is idle"
grep -F 'stop graphical-session.target' "$test_tmp/systemctl" >/dev/null &&
  fail "wrapper must not stop an inactive graphical-session target"
pass "idle graphical-session starts uwsm without a stop"

: >"$test_tmp/systemctl"
FAKE_GRAPHICAL_ACTIVE=1 FAKE_COMPOSITOR_RUNNING=0 run_starter
grep -F 'stop graphical-session.target graphical-session-pre.target' "$test_tmp/systemctl" >/dev/null ||
  fail "wrapper stops a leftover graphical-session target when Hyprland is not running"
grep -Fx 'UWSM:start -e -D Hyprland hyprland.desktop' "$test_tmp/uwsm" >/dev/null ||
  fail "wrapper still execs uwsm after clearing a stale target"
pass "stale graphical-session without compositor is cleared before uwsm"

: >"$test_tmp/systemctl"
FAKE_GRAPHICAL_ACTIVE=1 FAKE_COMPOSITOR_RUNNING=1 run_starter
grep -F 'stop graphical-session.target' "$test_tmp/systemctl" >/dev/null &&
  fail "wrapper must not stop graphical-session while Hyprland is running"
pass "live compositor is left alone"

# Sabotage: the stale-target stop is the actual fix. If it disappears, this fails.
if ! grep -F 'systemctl_user stop graphical-session.target graphical-session-pre.target' "$starter" >/dev/null; then
  fail "wrapper still contains the stale graphical-session stop"
fi
pass "stale-target stop is present in the wrapper"
