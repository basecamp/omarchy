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

# Real iw: `info` reports the nl80211 interface type, `link` reports only a
# station association -- an AP prints "Not connected." and an ad-hoc cell
# prints "Joined IBSS", neither of which is a dead radio.
cat >"$tmp_dir/bin/iw" <<'EOF'
#!/bin/bash
if [[ ${IW_FAIL:-0} == 1 ]]; then
  exit 1
fi
if [[ $3 == info ]]; then
  printf 'Interface %s\n\tifindex 3\n\twdev 0x1\n\ttype %s\n\twiphy 0\n' "$2" "${IW_TYPE:-managed}"
  exit 0
fi
case ${IW_TYPE:-managed} in
  AP | mesh)
    printf 'Not connected.\n'
    exit 0
    ;;
  IBSS)
    printf 'Joined IBSS aa:bb:cc:dd:ee:ff (on %s)\n' "$2"
    exit 0
    ;;
esac
if [[ ${IW_CONNECTED:-0} == 1 ]]; then
  printf 'Connected to aa:bb:cc:dd:ee:ff (on %s)\n' "$2"
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
  local dev=${1:-wlp9s0} blocked=${2:-0}

  mkdir -p "$tmp_dir/net/$dev/wireless" "$tmp_dir/net/$dev/phy80211/rfkill0"
  printf '%s\n' "$blocked" >"$tmp_dir/net/$dev/phy80211/rfkill0/soft"
  printf '0\n' >"$tmp_dir/net/$dev/phy80211/rfkill0/hard"
}

run_with_env() {
  RADIO="${RADIO:-enabled}" RFKILL_BLOCKED="${RFKILL_BLOCKED:-0}" \
    IW_CONNECTED="${IW_CONNECTED:-0}" NM_STATUS="${NM_STATUS:-}" \
    NMCLI_RC="${NMCLI_RC:-0}" NM_HANG="${NM_HANG:-0}" \
    GRANT_FAIL="${GRANT_FAIL:-0}" RESTART_FAIL="${RESTART_FAIL:-0}" \
    IW_TYPE="${IW_TYPE:-managed}" IW_FAIL="${IW_FAIL:-0}" \
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
    OMARCHY_WIFI_RECOVER_MAX_RELOADS="${MAX_RELOADS:-0}" \
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

rm -rf "$tmp_dir/net"; mkdir -p "$tmp_dir/net"; add_phy wlp9s0 1
NM_STATUS=$'wlp9s0:wifi:connected\n' RADIO=enabled IW_CONNECTED=0
if run_check >/dev/null; then
  fail "wifi recover leaves an rfkill-blocked radio alone"
fi
pass "wifi recover leaves an rfkill-blocked radio alone"

# A dongle the user blocked must not hold the wedged adapter beside it down.
rm -rf "$tmp_dir/net"; mkdir -p "$tmp_dir/net"
add_phy wlp9s0 0
add_phy wlx1 1
NM_STATUS=$'wlp9s0:wifi:connected\nwlx1:wifi:unavailable\n' IW_CONNECTED=0
if ! run_check >/dev/null; then
  fail "wifi recover still recovers a wedged radio beside a blocked one"
fi
pass "wifi recover still recovers a wedged radio beside a blocked one"
rm -rf "$tmp_dir/net"; mkdir -p "$tmp_dir/net"; add_phy

# Sitting disconnected on purpose is not a wedge.
NM_STATUS=$'wlp9s0:wifi:disconnected\n' RADIO=enabled RFKILL_BLOCKED=0 IW_CONNECTED=0
if run_check >/dev/null; then
  fail "wifi recover leaves a user-disconnected radio alone"
fi
pass "wifi recover leaves a user-disconnected radio alone"

# After a failed radio toggle: NM says unavailable, the phy is still listed
# in sysfs but the kernel no longer answers for it, radio on.
NM_STATUS=$'wlp9s0:wifi:unavailable\n' IW_FAIL=1
if ! run_check >/dev/null; then
  fail "wifi recover treats an unavailable phy with the radio on as wedged"
fi
pass "wifi recover treats an unavailable phy with the radio on as wedged"
IW_FAIL=0

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

# A hotspot is "connected" to NetworkManager with no station association.
# Unloading the driver under one drops every client on it.
NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0 IW_TYPE=AP
if run_check >/dev/null; then
  fail "wifi recover leaves a hosted access point alone"
fi
pass "wifi recover leaves a hosted access point alone"

NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0 IW_TYPE=IBSS
if run_check >/dev/null; then
  fail "wifi recover leaves an ad-hoc cell alone"
fi
pass "wifi recover leaves an ad-hoc cell alone"

NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0 IW_TYPE=mesh
if run_check >/dev/null; then
  fail "wifi recover leaves a mesh point alone"
fi
pass "wifi recover leaves a mesh point alone"
IW_TYPE=managed

# #7323: the quattro upgrade left wifi.backend=iwd with no iwd, so NM parks
# every device at unavailable while the driver is loaded and answering.
# Reloading it changes nothing, so the watcher must not.
NM_STATUS=$'wlp9s0:wifi:unavailable\n' IW_FAIL=0
if run_check >/dev/null; then
  fail "wifi recover leaves an unavailable device whose driver still answers alone"
fi
pass "wifi recover leaves an unavailable device whose driver still answers alone"

# The same NM state with a phy the kernel can no longer talk to is the wedge.
NM_STATUS=$'wlp9s0:wifi:unavailable\n' IW_FAIL=1
if ! run_check >/dev/null; then
  fail "wifi recover treats an unavailable device the kernel cannot reach as wedged"
fi
pass "wifi recover treats an unavailable device the kernel cannot reach as wedged"
IW_FAIL=0

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

# A phy that will not come back must not be unloaded every two minutes for
# the rest of the session. Stop after the cap, and say so once -- the old
# behaviour was silent after the first toast.
MAX_RELOADS=2 NM_STATUS=$'wlp9s0:wifi:connected\n' IW_CONNECTED=0 run_loop 6
(( $(restart_count) == 2 )) ||
  fail "wifi recover stops reloading after the cap" "$(cat "$tmp_dir/calls")"
(( $(grep -c 'notify .*did not come back' "$tmp_dir/calls") == 1 )) ||
  fail "wifi recover says once that it gave up" "$(cat "$tmp_dir/calls")"
grep -q 'gave up after 2 reloads' "$tmp_dir/err" ||
  fail "wifi recover logs that it gave up" "$(cat "$tmp_dir/err")"
pass "wifi recover stops reloading after the cap"
MAX_RELOADS=0

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

# Once the packaged unit is revised upstream, a stock staged copy no longer
# matches it. Matching the tree it was staged from is what stops it shadowing
# /usr/lib for good.
mkdir -p "$tmp_dir/revised/.config/systemd/user/graphical-session.target.wants" "$tmp_dir/lib2"
printf 'revised packaged unit\n' >"$tmp_dir/lib2/omarchy-wifi-recover.service"
install -Dm644 "$ROOT/default/systemd/user/omarchy-wifi-recover.service" \
  "$tmp_dir/revised/.config/systemd/user/omarchy-wifi-recover.service"
ln -sfn ../omarchy-wifi-recover.service \
  "$tmp_dir/revised/.config/systemd/user/graphical-session.target.wants/omarchy-wifi-recover.service"
HOME="$tmp_dir/revised" XDG_CONFIG_HOME="$tmp_dir/revised/.config" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/lib2/omarchy-wifi-recover.service" \
  OMARCHY_WIFI_NET_ROOT="$tmp_dir/net" RADIO=disabled \
  OMARCHY_WIFI_RECOVER_POLL=0 OMARCHY_WIFI_RECOVER_MAX_POLLS=1 \
  PATH="$tmp_dir/bin:$PATH" \
  "$ROOT/bin/omarchy-wifi-recover" >/dev/null || true
[[ ! -e $tmp_dir/revised/.config/systemd/user/omarchy-wifi-recover.service ]] ||
  fail "wifi recover unstages a stock copy after the packaged unit is revised"
pass "wifi recover unstages a stock copy after the packaged unit is revised"

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
grep -F 'sudo install -Dm440' "$ROOT/migrations/1787444800.sh" >/dev/null ||
  fail "migration does not install the sudoers grant"
pass "first-run unstages a packaged wifi recover unit"

# The migration runs on every existing install and had no test at all, which
# is how it came to disagree with the two other paths that stage this unit.
# Run it rather than grepping it. `visudo` and `systemctl` are absent or
# unusable in a test environment, and the runner supplies OMARCHY_PATH.
cat >"$tmp_dir/bin/visudo" <<'EOF'
#!/bin/bash
exit "${VISUDO_RC:-0}"
EOF
cat >"$tmp_dir/bin/systemctl" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "$tmp_dir/bin/visudo" "$tmp_dir/bin/systemctl"

mig_home="$tmp_dir/mig"
run_migration() {
  : >"$tmp_dir/calls"
  rm -rf "$mig_home"
  mkdir -p "$mig_home/.config/systemd/user"
  "$@"
  set +e
  CALLS="$tmp_dir/calls" HOME="$mig_home" XDG_CONFIG_HOME="$mig_home/.config" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_WIFI_SUDOERS_DEST="$tmp_dir/sudoers-dest" \
    OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/mig-packaged.service" \
    RESTART_FAIL="${MIG_SUDO_FAIL:-0}" VISUDO_RC="${MIG_VISUDO_RC:-0}" \
    PATH="$tmp_dir/bin:$PATH" \
    bash -euo pipefail "$ROOT/migrations/1787444800.sh" >"$tmp_dir/mig.out" 2>&1
  echo $? >"$tmp_dir/mig.rc"
  set -e
}

mig_staged="$mig_home/.config/systemd/user/omarchy-wifi-recover.service"
unit_src="$ROOT/default/systemd/user/omarchy-wifi-recover.service"
rm -f "$tmp_dir/sudoers-dest" "$tmp_dir/mig-packaged.service"

# A user who cancels the sudo prompt, or is not in %wheel, must not lose every
# migration queued behind this one.
MIG_SUDO_FAIL=1 run_migration true
[[ $(<"$tmp_dir/mig.rc") == 0 ]] ||
  fail "migration survives a refused sudo" "$(cat "$tmp_dir/mig.out")"
grep -q 'Could not install' "$tmp_dir/mig.out" ||
  fail "migration says the grant was not installed" "$(cat "$tmp_dir/mig.out")"
pass "migration survives a refused sudo"

MIG_VISUDO_RC=1 run_migration true
[[ $(<"$tmp_dir/mig.rc") == 0 ]] ||
  fail "migration survives an unparsable sudoers file" "$(cat "$tmp_dir/mig.out")"
grep -q 'does not parse' "$tmp_dir/mig.out" ||
  fail "migration says the sudoers file did not parse" "$(cat "$tmp_dir/mig.out")"
pass "migration reports an unparsable sudoers file"
MIG_VISUDO_RC=0

# Packaged unit present and the staged copy is stock: clean it up.
run_migration cp "$unit_src" "$tmp_dir/mig-packaged.service"
install -Dm644 "$unit_src" "$mig_staged"
CALLS="$tmp_dir/calls" HOME="$mig_home" XDG_CONFIG_HOME="$mig_home/.config" \
  OMARCHY_PATH="$ROOT" OMARCHY_WIFI_SUDOERS_DEST="$tmp_dir/sudoers-dest" \
  OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/mig-packaged.service" \
  PATH="$tmp_dir/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1787444800.sh" >/dev/null 2>&1
[[ ! -e $mig_staged ]] ||
  fail "migration removes a stock staged unit once the packaged one exists"
pass "migration removes a stock staged unit once the packaged one exists"

# The same, with the user's own edits in it. The watcher and first-run both
# leave that alone; the migration used to delete it.
printf 'customized\n' >"$mig_staged"
CALLS="$tmp_dir/calls" HOME="$mig_home" XDG_CONFIG_HOME="$mig_home/.config" \
  OMARCHY_PATH="$ROOT" OMARCHY_WIFI_SUDOERS_DEST="$tmp_dir/sudoers-dest" \
  OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/mig-packaged.service" \
  PATH="$tmp_dir/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1787444800.sh" >/dev/null 2>&1
[[ $(<"$mig_staged") == customized ]] ||
  fail "migration leaves a customized staged unit alone"
pass "migration leaves a customized staged unit alone"

# No packaged unit yet: stage ours, but never over the user's.
rm -f "$tmp_dir/mig-packaged.service"
run_migration true
cmp -s "$mig_staged" "$unit_src" ||
  fail "migration stages the unit when no packaged copy exists"
pass "migration stages the unit when no packaged copy exists"

printf 'customized\n' >"$mig_staged"
CALLS="$tmp_dir/calls" HOME="$mig_home" XDG_CONFIG_HOME="$mig_home/.config" \
  OMARCHY_PATH="$ROOT" OMARCHY_WIFI_SUDOERS_DEST="$tmp_dir/sudoers-dest" \
  OMARCHY_WIFI_RECOVER_PACKAGED_UNIT="$tmp_dir/mig-packaged.service" \
  PATH="$tmp_dir/bin:$PATH" \
  bash -euo pipefail "$ROOT/migrations/1787444800.sh" >/dev/null 2>&1
[[ $(<"$mig_staged") == customized ]] ||
  fail "migration does not restage over a customized unit"
pass "migration does not restage over a customized unit"

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
