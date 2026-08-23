#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/net"

cat >"$tmp_dir/bin/nmcli" <<'EOF'
#!/bin/bash
if [[ ${NM_HANG:-0} == 1 ]]; then
  sleep 100
  exit 0
fi
if [[ ${NMCLI_RC:-0} != 0 ]]; then
  exit "$NMCLI_RC"
fi
if [[ $1 == radio && $2 == wifi ]]; then
  printf '%s\n' "${RADIO:-enabled}"
  exit 0
fi
if [[ $1 == -t && $2 == -f && $3 == DEVICE,TYPE,STATE ]]; then
  printf '%s\n' "${NM_STATUS:-}"
  exit 0
fi
exit 0
EOF

cat >"$tmp_dir/bin/rfkill" <<'EOF'
#!/bin/bash
if [[ ${RFKILL_BLOCKED:-0} == 1 ]]; then
  printf '0: phy0: Wireless LAN\n\tSoft blocked: yes\n\tHard blocked: no\n'
  exit 0
fi
printf '0: phy0: Wireless LAN\n\tSoft blocked: no\n\tHard blocked: no\n'
EOF

cat >"$tmp_dir/bin/iw" <<'EOF'
#!/bin/bash
if [[ ${IW_CONNECTED:-0} == 1 ]]; then
  printf 'Connected to aa:bb:cc:dd:ee:ff (on wlp9s0)\n'
  exit 0
fi
printf 'Not connected.\n'
EOF

cat >"$tmp_dir/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"
if [[ $1 == -n && $2 == -l ]]; then
  if [[ ${GRANT_FAIL:-0} == 1 ]]; then
    exit 1
  fi
  printf '!authenticate\n'
  exit 0
fi
if [[ ${RESTART_FAIL:-0} == 1 ]]; then
  exit 1
fi
exit 0
EOF

cat >"$tmp_dir/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$CALLS"
EOF

chmod +x "$tmp_dir/bin"/*

add_phy() {
  mkdir -p "$tmp_dir/net/wlp9s0/wireless"
}

run_with_env() {
  RADIO="${RADIO:-enabled}" RFKILL_BLOCKED="${RFKILL_BLOCKED:-0}" \
    IW_CONNECTED="${IW_CONNECTED:-0}" NM_STATUS="${NM_STATUS:-}" \
    NMCLI_RC="${NMCLI_RC:-0}" NM_HANG="${NM_HANG:-0}" \
    GRANT_FAIL="${GRANT_FAIL:-0}" RESTART_FAIL="${RESTART_FAIL:-0}" \
    OMARCHY_WIFI_NET_ROOT="$tmp_dir/net" \
    OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="${OMARCHY_WIFI_RECOVER_PACKAGED_UNIT:-$tmp_dir/no-packaged-unit}" \
    OMARCHY_WIFI_RECOVER_NM_TIMEOUT="${OMARCHY_WIFI_RECOVER_NM_TIMEOUT:-10}" \
    PATH="$tmp_dir/bin:$PATH" \
    "$@"
}

run_check() {
  run_with_env "$ROOT/bin/omarchy-wifi-recover" --check
}

run_once() {
  : >"$tmp_dir/calls"
  CALLS="$tmp_dir/calls" run_with_env \
    env OMARCHY_WIFI_RECOVER_ONCE=1 OMARCHY_WIFI_RECOVER_COOLDOWN=0 \
    "$ROOT/bin/omarchy-wifi-recover" >/dev/null
}

run_loop() {
  local max=$1
  : >"$tmp_dir/calls"
  : >"$tmp_dir/err"
  CALLS="$tmp_dir/calls" run_with_env \
    env OMARCHY_WIFI_RECOVER_POLL=0 OMARCHY_WIFI_RECOVER_CONFIRM=2 \
    OMARCHY_WIFI_RECOVER_COOLDOWN=0 OMARCHY_WIFI_RECOVER_MAX_POLLS=$max \
    "$ROOT/bin/omarchy-wifi-recover" >/dev/null 2>"$tmp_dir/err"
}

restart_count() {
  grep -c '^sudo -n /usr/bin/omarchy-restart-wifi$' "$tmp_dir/calls"
}

add_phy

# The mid-session AX210 hang: NM still says connected, the kernel link is gone.
NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0
if ! run_check >/dev/null; then
  fail "wifi recover treats a connected device with no kernel link as wedged"
fi
pass "wifi recover treats a connected device with no kernel link as wedged"

NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=1
if run_check >/dev/null; then
  fail "wifi recover leaves a healthy association alone"
fi
pass "wifi recover leaves a healthy association alone"

# User turned the radio off, or rfkill is on. Do not fight them.
NM_STATUS=$'wlp9s0:wifi:unavailable\n' RADIO=disabled
if run_check >/dev/null; then
  fail "wifi recover leaves a user-disabled radio alone"
fi
pass "wifi recover leaves a user-disabled radio alone"

NM_STATUS=$'wlp9s0:wifi:unavailable\n' RADIO=enabled RFKILL_BLOCKED=1
if run_check >/dev/null; then
  fail "wifi recover leaves an rfkill-blocked radio alone"
fi
pass "wifi recover leaves an rfkill-blocked radio alone"

# Sitting disconnected on purpose is not a wedge.
NM_STATUS=$'wlp9s0:wifi:disconnected\n' RADIO=enabled RFKILL_BLOCKED=0 IW_CONNECTED=0
if run_check >/dev/null; then
  fail "wifi recover leaves a user-disconnected radio alone"
fi
pass "wifi recover leaves a user-disconnected radio alone"

# After a failed radio toggle: NM says unavailable, phy is still there, radio on.
NM_STATUS=$'wlp9s0:wifi:unavailable\n'
if ! run_check >/dev/null; then
  fail "wifi recover treats an unavailable phy with the radio on as wedged"
fi
pass "wifi recover treats an unavailable phy with the radio on as wedged"

# NM crash-looping is not a firmware wedge.
NMCLI_RC=8 NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0
if run_check >/dev/null; then
  fail "wifi recover leaves a down NetworkManager alone"
fi
pass "wifi recover leaves a down NetworkManager alone"
NMCLI_RC=0

# NM listed no wifi device but the phy is still in sysfs.
add_phy
NM_STATUS=""
if ! run_check >/dev/null; then
  fail "wifi recover treats a phy NM cannot see as wedged"
fi
pass "wifi recover treats a phy NM cannot see as wedged"

NM_STATUS=$'wlp9s0:wifi:connecting\n' IW_CONNECTED=0
if run_check >/dev/null; then
  fail "wifi recover leaves a connecting radio alone"
fi
pass "wifi recover leaves a connecting radio alone"

NM_HANG=1 OMARCHY_WIFI_RECOVER_NM_TIMEOUT=1
if ! run_check >/dev/null; then
  fail "wifi recover treats a hung nmcli as wedged"
fi
pass "wifi recover treats a hung nmcli as wedged"
NM_HANG=0
unset OMARCHY_WIFI_RECOVER_NM_TIMEOUT

# No wireless hardware at all.
rm -rf "$tmp_dir/net"
mkdir -p "$tmp_dir/net"
NM_STATUS=""
if run_check >/dev/null; then
  fail "wifi recover does nothing on a machine with no radio"
fi
pass "wifi recover does nothing on a machine with no radio"

add_phy
NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0
run_once
grep -qx 'sudo -n /usr/bin/omarchy-restart-wifi' "$tmp_dir/calls" ||
  fail "wifi recover reloads through the packaged restart command" "$(cat "$tmp_dir/calls")"
grep -q 'notify ' "$tmp_dir/calls" ||
  fail "wifi recover tells the user it reloaded the radio" "$(cat "$tmp_dir/calls")"
pass "wifi recover reloads through the packaged restart command"

NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=1
run_once
grep -q 'sudo' "$tmp_dir/calls" &&
  fail "wifi recover does not reload a healthy radio" "$(cat "$tmp_dir/calls")"
pass "wifi recover does not reload a healthy radio"

# A single connected-without-link poll is a roam or a radio-on race.
NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0
run_loop 1
grep -q 'sudo' "$tmp_dir/calls" &&
  fail "wifi recover does not reload on a single missed link poll" "$(cat "$tmp_dir/calls")"
pass "wifi recover does not reload on a single missed link poll"

run_loop 2
grep -qx 'sudo -n /usr/bin/omarchy-restart-wifi' "$tmp_dir/calls" ||
  fail "wifi recover reloads after two missed link polls" "$(cat "$tmp_dir/calls")"
pass "wifi recover reloads after two missed link polls"

# A permanently dead phy must not toast every cooldown.
run_loop 4
(( $(grep -c '^notify ' "$tmp_dir/calls") == 1 )) ||
  fail "wifi recover toasts once per wedge episode" "$(cat "$tmp_dir/calls")"
(( $(restart_count) == 3 )) ||
  fail "wifi recover still retries the reload after the first toast" "$(cat "$tmp_dir/calls")"
pass "wifi recover toasts once per wedge episode"

# Missing grant: warn once, never toast, never run the restart command.
GRANT_FAIL=1 NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0 run_loop 4
(( $(grep -c 'sudo -n -l -l' "$tmp_dir/calls") == 3 )) ||
  fail "wifi recover rechecks the grant while it is missing" "$(cat "$tmp_dir/calls")"
(( $(restart_count) == 0 )) ||
  fail "wifi recover does not run restart-wifi without a grant" "$(cat "$tmp_dir/calls")"
grep -q 'notify ' "$tmp_dir/calls" &&
  fail "wifi recover does not toast a missing grant" "$(cat "$tmp_dir/calls")"
(( $(grep -c 'passwordless sudo' "$tmp_dir/err") == 1 )) ||
  fail "wifi recover warns once when the grant is missing" "$(cat "$tmp_dir/err")"
pass "wifi recover does not toast when sudo is denied"
GRANT_FAIL=0

# Reload ran but failed: cooldown, no success toast.
RESTART_FAIL=1 NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0 run_loop 4
(( $(restart_count) == 3 )) ||
  fail "wifi recover retries a failed reload" "$(cat "$tmp_dir/calls")"
grep -q 'notify ' "$tmp_dir/calls" &&
  fail "wifi recover does not toast a failed reload" "$(cat "$tmp_dir/calls")"
grep -q 'omarchy-restart-wifi failed' "$tmp_dir/err" ||
  fail "wifi recover reports a failed reload" "$(cat "$tmp_dir/err")"
pass "wifi recover does not toast a failed reload"
RESTART_FAIL=0
# Staged ~/.config unit must not shadow a later packaged copy.
# Unstage runs only in the daemon path, not --check/ONCE.
mkdir -p "$tmp_dir/home/.config/systemd/user/graphical-session.target.wants" "$tmp_dir/lib"
touch "$tmp_dir/lib/omarchy-wifi-recover.service" \
  "$tmp_dir/home/.config/systemd/user/omarchy-wifi-recover.service"
ln -sfn ../omarchy-wifi-recover.service \
  "$tmp_dir/home/.config/systemd/user/graphical-session.target.wants/omarchy-wifi-recover.service"
HOME="$tmp_dir/home" XDG_CONFIG_HOME="$tmp_dir/home/.config" \
  OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/lib/omarchy-wifi-recover.service" \
  OMARCHY_WIFI_NET_ROOT="$tmp_dir/net" RADIO=disabled \
  OMARCHY_WIFI_RECOVER_POLL=0 OMARCHY_WIFI_RECOVER_MAX_POLLS=1 \
  PATH="$tmp_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-wifi-recover" >/dev/null || true
[[ ! -e $tmp_dir/home/.config/systemd/user/omarchy-wifi-recover.service ]] ||
  fail "wifi recover removes a staged unit once the packaged one exists"
[[ $(readlink "$tmp_dir/home/.config/systemd/user/graphical-session.target.wants/omarchy-wifi-recover.service") == "$tmp_dir/lib/omarchy-wifi-recover.service" ]] ||
  fail "wifi recover re-points the wants symlink at the packaged unit"
pass "wifi recover removes a staged unit once the packaged one exists"

# A user-edited staged unit must not be deleted.
mkdir -p "$tmp_dir/custom/.config/systemd/user" "$tmp_dir/lib"
printf 'packaged\n' >"$tmp_dir/lib/omarchy-wifi-recover.service"
printf 'customized\n' >"$tmp_dir/custom/.config/systemd/user/omarchy-wifi-recover.service"
HOME="$tmp_dir/custom" XDG_CONFIG_HOME="$tmp_dir/custom/.config" \
  OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/lib/omarchy-wifi-recover.service" \
  OMARCHY_WIFI_NET_ROOT="$tmp_dir/net" RADIO=disabled \
  OMARCHY_WIFI_RECOVER_POLL=0 OMARCHY_WIFI_RECOVER_MAX_POLLS=1 \
  PATH="$tmp_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-wifi-recover" >/dev/null || true
[[ $(<"$tmp_dir/custom/.config/systemd/user/omarchy-wifi-recover.service") == customized ]] ||
  fail "wifi recover leaves a customized staged unit alone"
pass "wifi recover leaves a customized staged unit alone"


grep -F 'timeout "$IW_TIMEOUT" iw' "$ROOT/bin/omarchy-wifi-recover" >/dev/null ||
  fail "wifi recover does not bound iw probes"
grep -F 'timeout "$NM_TIMEOUT" nmcli' "$ROOT/bin/omarchy-wifi-recover" >/dev/null ||
  fail "wifi recover does not bound nmcli probes"
pass "wifi recover bounds iw and nmcli probes"

grep -F 'rm -f "$staged"' "$ROOT/install/user/first-run/enable-user-units.sh" >/dev/null ||
  fail "first-run does not unstage a packaged wifi recover unit"
grep -F 'rm -f "$config_home/systemd/user/omarchy-wifi-recover.service"' \
  "$ROOT/migrations/1787444800.sh" >/dev/null ||
  fail "migration does not unstage a packaged wifi recover unit"
grep -F 'sudo install -Dm440' "$ROOT/migrations/1787444800.sh" >/dev/null ||
  fail "migration does not install the sudoers grant"
pass "first-run and migration unstage a packaged wifi recover unit"

sudoers="$ROOT/etc/sudoers.d/omarchy-restart-wifi"
rule='%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-restart-wifi ""'
rules=$(grep -vE '^[[:space:]]*(#|$)' "$sudoers")
[[ $rules == "$rule" ]] ||
  fail "wifi sudoers file grants only omarchy-restart-wifi with no args" "got: $rules"
if command -v visudo >/dev/null; then
  visudo -cf "$sudoers" >/dev/null || fail "wifi sudoers rule parses"
fi
pass "wifi sudoers rule is scoped to omarchy-restart-wifi"

service="$ROOT/default/systemd/user/omarchy-wifi-recover.service"
grep -Fx 'ExecStart=/usr/bin/omarchy-wifi-recover' "$service" >/dev/null ||
  fail "wifi recover unit starts the packaged watcher"
grep -Fx 'WantedBy=graphical-session.target' "$service" >/dev/null ||
  fail "wifi recover unit is pulled in at login"
grep -Fx 'ConditionPathExists=/sys/class/ieee80211' "$service" >/dev/null ||
  fail "wifi recover unit stays off machines with no phy"
grep -Fx 'ConditionPathExists=/usr/bin/omarchy-wifi-recover' "$service" >/dev/null ||
  fail "wifi recover unit stays off until the packaged binary exists"
pass "wifi recover unit starts with the graphical session"

migration=$(grep -rl 'omarchy-wifi-recover.service' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "existing installs never enable wifi recover"
grep -F 'systemctl --user enable omarchy-wifi-recover.service' "$migration" >/dev/null ||
  fail "wifi recover migration enables the unit"
pass "existing installs enable wifi recover"

mode=$(stat -c '%a' "$ROOT/migrations/1787444800.sh")
[[ $mode == 644 ]] || fail "wifi recover migration must be mode 644" "$mode"
pass "wifi recover migration is mode 644"
