#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin" "$tmp_dir/net"

cat >"$tmp_dir/bin/rfkill" <<'EOF'
#!/bin/bash
printf 'rfkill %s\n' "$*" >>"$CALLS"
if [[ $1 == list ]]; then
  printf '0: phy0: Wireless LAN\n\tSoft blocked: no\n\tHard blocked: no\n'
fi
EOF

cat >"$tmp_dir/bin/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli %s\n' "$*" >>"$CALLS"
EOF

cat >"$tmp_dir/bin/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"
exec "$@"
EOF

cat >"$tmp_dir/bin/modprobe" <<'EOF'
#!/bin/bash
printf 'modprobe %s\n' "$*" >>"$CALLS"
EOF

cat >"$tmp_dir/bin/lsmod" <<'EOF'
#!/bin/bash
cat "$LSMOD_FILE"
EOF

chmod +x "$tmp_dir/bin"/*

add_iface() {
  local name=$1
  local driver=$2

  mkdir -p "$tmp_dir/net/$name/wireless" "$tmp_dir/net/$name/device" "$tmp_dir/drivers/$driver"
  ln -sfn "$tmp_dir/drivers/$driver" "$tmp_dir/net/$name/device/driver"
}

run_restart() {
  : >"$tmp_dir/calls"
  set +e
  CALLS="$tmp_dir/calls" LSMOD_FILE="$tmp_dir/lsmod" \
    OMARCHY_WIFI_NET_ROOT="$tmp_dir/net" \
    PATH="$tmp_dir/bin:$PATH" \
    "$ROOT/bin/omarchy-restart-wifi" >/dev/null
  echo $? >"$tmp_dir/rc"
  set -e
}

# A wedged AX210 is the case this command used to miss: rfkill was already
# clear, and only unloading iwlmvm+iwlwifi brought the firmware back.
printf 'iwlmvm 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
add_iface wlp9s0 iwlwifi
run_restart

grep -qx 'rfkill unblock wifi' "$tmp_dir/calls" ||
  fail "wifi still lifts the rfkill block" "$(cat "$tmp_dir/calls")"
grep -qx 'sudo modprobe -r -- iwlmvm iwlwifi' "$tmp_dir/calls" ||
  fail "wifi unloads iwlmvm before iwlwifi" "$(cat "$tmp_dir/calls")"
grep -qx 'sudo modprobe -- iwlwifi' "$tmp_dir/calls" ||
  fail "wifi reloads iwlwifi" "$(cat "$tmp_dir/calls")"
grep -qx 'nmcli radio wifi on' "$tmp_dir/calls" ||
  fail "wifi turns the radio back on after the reload" "$(cat "$tmp_dir/calls")"
pass "wifi reloads a wedged iwlwifi/iwlmvm radio"

[[ $(<"$tmp_dir/rc") == 0 ]] ||
  fail "wifi reports success when the driver reloads" "$(cat "$tmp_dir/rc")"
pass "wifi reports success when the driver reloads"

# BE200+ uses iwlmld, not iwlmvm. Same PCI driver name, different helper.
printf 'iwlmld 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlan0 iwlwifi
run_restart

grep -qx 'sudo modprobe -r -- iwlmld iwlwifi' "$tmp_dir/calls" ||
  fail "wifi unloads iwlmld before iwlwifi" "$(cat "$tmp_dir/calls")"
pass "wifi reloads a wedged iwlwifi/iwlmld radio"


# Older Intel cards use iwldvm.
printf 'iwldvm 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlan0 iwlwifi
run_restart

grep -qx 'sudo modprobe -r -- iwldvm iwlwifi' "$tmp_dir/calls" ||
  fail "wifi unloads iwldvm before iwlwifi" "$(cat "$tmp_dir/calls")"
pass "wifi reloads a wedged iwlwifi/iwldvm radio"



# RTL8852BE (#7003) binds as rtw89_8852be. There is no Intel-style helper.
printf 'rtw89_8852be 1 0\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp2s0 rtw89_8852be
run_restart

grep -qx 'sudo modprobe -r -- rtw89_8852be' "$tmp_dir/calls" ||
  fail "wifi unloads the Realtek PCI driver" "$(cat "$tmp_dir/calls")"
grep -qx 'sudo modprobe -- rtw89_8852be' "$tmp_dir/calls" ||
  fail "wifi reloads the Realtek PCI driver" "$(cat "$tmp_dir/calls")"
grep -q iwlwifi "$tmp_dir/calls" &&
  fail "wifi does not touch iwlwifi on a Realtek radio" "$(cat "$tmp_dir/calls")"
pass "wifi reloads a wedged rtw89 radio"

# Two virtual interfaces on one phy must not unload the driver twice.
printf 'iwlmvm 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp9s0 iwlwifi
add_iface p2p-dev-wlp9s0 iwlwifi
run_restart

unload_count=$(grep -c 'sudo modprobe -r -- iwlmvm iwlwifi' "$tmp_dir/calls" || true)
(( unload_count == 1 )) ||
  fail "wifi reloads a shared driver once" "$(cat "$tmp_dir/calls")"
pass "wifi reloads a shared driver once"

# No wireless device: still unblock and turn the radio on.
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
printf '' >"$tmp_dir/lsmod"
run_restart

grep -q 'modprobe' "$tmp_dir/calls" &&
  fail "wifi does not reload a driver when none is bound" "$(cat "$tmp_dir/calls")"
grep -qx 'rfkill unblock wifi' "$tmp_dir/calls" ||
  fail "wifi still unblocks when no device is present" "$(cat "$tmp_dir/calls")"
grep -qx 'nmcli radio wifi on' "$tmp_dir/calls" ||
  fail "wifi still enables the radio when no device is present" "$(cat "$tmp_dir/calls")"
pass "wifi skips the reload when no radio is bound"

[[ $(<"$tmp_dir/rc") == 0 ]] ||
  fail "wifi still succeeds when there is no driver to reload" "$(cat "$tmp_dir/rc")"

# A failed unload must not look like success to the watcher.
cat >"$tmp_dir/bin/modprobe" <<'EOF'
#!/bin/bash
printf 'modprobe %s\n' "$*" >>"$CALLS"
[[ $1 == -r ]] && exit 1
exit 0
EOF
chmod +x "$tmp_dir/bin/modprobe"
printf 'iwlmvm 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp9s0 iwlwifi
run_restart
[[ $(<"$tmp_dir/rc") == 1 ]] ||
  fail "wifi reports a failed driver unload" "$(cat "$tmp_dir/rc"; cat "$tmp_dir/calls")"
grep -qx 'sudo modprobe -- iwlwifi' "$tmp_dir/calls" &&
  fail "wifi does not reload after a failed unload" "$(cat "$tmp_dir/calls")"
pass "wifi reports a failed driver unload"

# Unload succeeded, insert failed: retry insert and do not exit 0.
cat >"$tmp_dir/bin/modprobe" <<'EOF'
#!/bin/bash
printf 'modprobe %s\n' "$*" >>"$CALLS"
[[ $1 == -r ]] && exit 0
exit 1
EOF
chmod +x "$tmp_dir/bin/modprobe"
printf 'iwlmvm 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp9s0 iwlwifi
run_restart
[[ $(<"$tmp_dir/rc") == 1 ]] ||
  fail "wifi reports a failed driver insert" "$(cat "$tmp_dir/rc"; cat "$tmp_dir/calls")"
(( $(grep -c 'sudo modprobe -- iwlwifi' "$tmp_dir/calls" || true) >= 2 )) ||
  fail "wifi retries a failed insert" "$(cat "$tmp_dir/calls")"
pass "wifi reports a failed driver insert"

# iwlmei pins iwlwifi on Intel platforms that ship the management engine
# interface, and modprobe -r fails while it is loaded.
cat >"$tmp_dir/bin/modprobe" <<'EOF'
#!/bin/bash
printf 'modprobe %s\n' "$*" >>"$CALLS"
EOF
chmod +x "$tmp_dir/bin/modprobe"
printf 'iwlmei 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp9s0 iwlwifi
run_restart

grep -qx 'sudo modprobe -r -- iwlmei iwlwifi' "$tmp_dir/calls" ||
  fail "wifi unloads iwlmei before iwlwifi" "$(cat "$tmp_dir/calls")"
pass "wifi unloads iwlmei before iwlwifi"

# One busy driver must not leave a working adapter dark. The radio toggle is
# what brings the reloaded one back, so it has to run regardless.
cat >"$tmp_dir/bin/modprobe" <<'EOF'
#!/bin/bash
printf 'modprobe %s\n' "$*" >>"$CALLS"
[[ $* == *rtw89_8852be* ]] && exit 1
exit 0
EOF
chmod +x "$tmp_dir/bin/modprobe"
printf 'iwlmvm 1 0\niwlwifi 1 1\nrtw89_8852be 1 0\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp9s0 iwlwifi
add_iface wlp2s0 rtw89_8852be
run_restart

grep -qx 'sudo modprobe -- iwlwifi' "$tmp_dir/calls" ||
  fail "wifi reloads the driver that can be reloaded" "$(cat "$tmp_dir/calls")"
grep -qx 'nmcli radio wifi on' "$tmp_dir/calls" ||
  fail "wifi turns the radio back on for the adapter that did reload" "$(cat "$tmp_dir/calls")"
[[ $(<"$tmp_dir/rc") == 1 ]] ||
  fail "wifi still reports the driver that failed" "$(cat "$tmp_dir/rc")"
pass "wifi restores the radio for the adapter that did reload"

# NetworkManager refusing the radio is not a recovery. The watcher toasts on
# exit 0, so this has to be the difference between success and failure.
cat >"$tmp_dir/bin/modprobe" <<'EOF'
#!/bin/bash
printf 'modprobe %s\n' "$*" >>"$CALLS"
EOF
cat >"$tmp_dir/bin/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli %s\n' "$*" >>"$CALLS"
[[ $1 == radio ]] && exit 1
exit 0
EOF
chmod +x "$tmp_dir/bin/modprobe" "$tmp_dir/bin/nmcli"
printf 'iwlmvm 1 0\niwlwifi 1 1\n' >"$tmp_dir/lsmod"
rm -rf "$tmp_dir/net" "$tmp_dir/drivers"
mkdir -p "$tmp_dir/net"
add_iface wlp9s0 iwlwifi
run_restart

[[ $(<"$tmp_dir/rc") == 1 ]] ||
  fail "wifi reports a radio NetworkManager would not turn on" "$(cat "$tmp_dir/rc"; cat "$tmp_dir/calls")"
pass "wifi reports a radio NetworkManager would not turn on"

cat >"$tmp_dir/bin/nmcli" <<'EOF'
#!/bin/bash
printf 'nmcli %s\n' "$*" >>"$CALLS"
EOF
chmod +x "$tmp_dir/bin/nmcli"

grep -F 'omarchy-restart-wifi' "$ROOT/default/omarchy/omarchy-menu.jsonc" >/dev/null ||
  fail "the hardware menu still points at omarchy-restart-wifi"
pass "the hardware menu still points at omarchy-restart-wifi"
