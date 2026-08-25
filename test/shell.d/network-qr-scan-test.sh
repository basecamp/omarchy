#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat >"$tmp/bin/omarchy-capture-webcam-list" <<'SH'
#!/bin/bash
printf '%s' "${TEST_CAMERAS:-}"
SH

cat >"$tmp/bin/omarchy-menu-select" <<'SH'
#!/bin/bash
printf 'menu' >>"$TEST_CALLS"
printf '\t%s' "$@" >>"$TEST_CALLS"
printf '\n' >>"$TEST_CALLS"
if [[ -n ${TEST_PICKER_READY:-} ]]; then
  trap 'touch "$TEST_PICKER_STOPPED"; exit 130' TERM
  touch "$TEST_PICKER_READY"
  while :; do sleep 0.05; done
fi
(( ${TEST_PICKER_STATUS:-0} == 0 )) || exit "$TEST_PICKER_STATUS"
printf '%s' "${TEST_PICKER_SELECTION:-}"
SH

cat >"$tmp/bin/zbarcam" <<'SH'
#!/bin/bash
printf 'zbarcam' >>"$TEST_CALLS"
printf '\t%s' "$@" >>"$TEST_CALLS"
printf '\n' >>"$TEST_CALLS"
printf '%s' "${TEST_SCAN_RESULT:-}"
SH

cat >"$tmp/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf 'omarchy-shell' >>"$TEST_CALLS"
printf '\t%s' "$@" >>"$TEST_CALLS"
printf '\n' >>"$TEST_CALLS"
SH

cat >"$tmp/bin/nmcli" <<'SH'
#!/bin/bash
printf 'nmcli' >>"$TEST_CALLS"
printf '\t%s' "$@" >>"$TEST_CALLS"
printf '\n' >>"$TEST_CALLS"

if [[ ${1:-} == "connection" && ${2:-} == "add" ]]; then
  while (( $# > 0 )); do
    if [[ $1 == "connection.uuid" ]]; then
      printf '%s' "$2" >"$TEST_CREATED_UUID"
      break
    fi
    shift
  done
fi

if [[ ${1:-} == "connection" && ${2:-} == "edit" ]]; then
  while IFS= read -r line || [[ -n $line ]]; do
    printf '%s\n' "$line" >>"$TEST_EDIT_INPUT"
  done
fi

if [[ ${1:-} == "connection" && ${2:-} == "delete" ]]; then
  printf '%s' "${4:-}" >"$TEST_DELETED_UUID"
fi

if [[ ${1:-} == "connection" && ${2:-} == "up" && -n ${TEST_UP_READY:-} ]]; then
  trap 'touch "$TEST_UP_STOPPED"; exit 130' TERM
  touch "$TEST_UP_READY"
  while :; do sleep 0.05; done
fi

[[ -z ${TEST_NMCLI_FAIL_ON:-} || " $* " != *" $TEST_NMCLI_FAIL_ON "* ]]
SH

chmod +x "$tmp/bin"/*

scan="$ROOT/bin/omarchy-network-qr-scan"
connect="$ROOT/bin/omarchy-network-connect-qr"
calls="$tmp/calls"

: >"$calls"
if TEST_CAMERAS="" TEST_CALLS="$calls" PATH="$tmp/bin:$PATH" "$scan" >"$tmp/out" 2>"$tmp/error"; then
  fail "webcam QR scanner fails when no camera is available"
fi
[[ $(<"$tmp/error") == "No webcam devices found" ]] || fail "webcam QR scanner reports the missing camera clearly" "$(<"$tmp/error")"
[[ ! -s $calls ]] || fail "webcam QR scanner does not launch a scanner without a camera" "$(<"$calls")"
pass "webcam QR scanner fails clearly when no camera is available"

: >"$calls"
scan_output=$(TEST_CAMERAS="/dev/video2  Built-in Camera" TEST_SCAN_RESULT="WIFI:data" TEST_CALLS="$calls" PATH="$tmp/bin:$PATH" "$scan")
[[ $scan_output == "WIFI:data" ]] || fail "webcam QR scanner returns zbar output"
expected_zbar=$'zbarcam\t--oneshot\t--raw\t--quiet\t--nodbus\t-Sdisable\t-Sqrcode.enable\t/dev/video2'
[[ $(<"$calls") == "$expected_zbar" ]] || fail "webcam QR scanner uses one-shot QR-only flags and the sole camera" "$(<"$calls")"
[[ $(<"$calls") != *--nodisplay* ]] || fail "webcam QR scanner leaves the preview visible"
pass "webcam QR scanner uses the sole camera with a visible QR-only preview"

: >"$calls"
TEST_CAMERAS=$'/dev/video0  Front Camera\n/dev/video4  USB Camera' \
  TEST_PICKER_SELECTION="/dev/video4  USB Camera" TEST_CALLS="$calls" PATH="$tmp/bin:$PATH" "$scan" >/dev/null
mapfile -t scan_calls <"$calls"
[[ ${scan_calls[0]} == $'menu\tSelect Webcam\t/dev/video0  Front Camera\t/dev/video4  USB Camera\t--\t--width\t520\t--maxheight\t520' ]] ||
  fail "webcam QR scanner offers multiple cameras to the picker" "${scan_calls[0]}"
[[ ${scan_calls[1]} == $'zbarcam\t--oneshot\t--raw\t--quiet\t--nodbus\t-Sdisable\t-Sqrcode.enable\t/dev/video4' ]] ||
  fail "webcam QR scanner scans with the selected camera" "${scan_calls[1]}"
pass "webcam QR scanner picks among multiple cameras"

: >"$calls"
if ! TEST_CAMERAS=$'/dev/video0  Front Camera\n/dev/video4  USB Camera' TEST_PICKER_STATUS=1 \
  TEST_CALLS="$calls" PATH="$tmp/bin:$PATH" "$scan" >/dev/null; then
  fail "webcam QR scanner treats picker cancellation as clean cancellation"
fi
[[ $(<"$calls") == menu$'\t'* ]] || fail "webcam QR scanner opens the picker before cancellation" "$(<"$calls")"
[[ $(<"$calls") != *zbarcam* ]] || fail "webcam QR scanner does not start zbar after picker cancellation" "$(<"$calls")"
pass "webcam QR scanner handles picker cancellation cleanly"

: >"$calls"
picker_ready="$tmp/picker-ready"
picker_stopped="$tmp/picker-stopped"
TEST_CAMERAS=$'/dev/video0  Front Camera\n/dev/video4  USB Camera' TEST_PICKER_READY="$picker_ready" \
  TEST_PICKER_STOPPED="$picker_stopped" TEST_CALLS="$calls" PATH="$tmp/bin:$PATH" "$scan" >/dev/null 2>&1 &
scan_pid=$!
for _ in {1..100}; do [[ -e $picker_ready ]] && break; sleep 0.01; done
[[ -e $picker_ready ]] || fail "webcam QR scanner starts the camera picker for cancellation coverage"
kill "$scan_pid"
wait "$scan_pid" 2>/dev/null || true
[[ -e $picker_stopped ]] || fail "webcam QR scanner terminates its camera picker when canceled"
[[ $(<"$calls") == *$'omarchy-shell\tshell\thide\tomarchy.menu'* ]] ||
  fail "webcam QR scanner dismisses the camera picker UI when canceled" "$(<"$calls")"
pass "webcam QR scanner terminates an active camera picker"

scanner_rules="$ROOT/default/hypr/apps/wifi-qr-scanner.lua"
grep -F 'o.window("^zbar$", {' "$scanner_rules" >/dev/null || fail "Wi-Fi QR preview matches the zbar window class"
grep -F 'float = true' "$scanner_rules" >/dev/null || fail "Wi-Fi QR preview floats"
grep -F 'no_initial_focus = true' "$scanner_rules" >/dev/null || fail "Wi-Fi QR preview leaves keyboard focus on the network panel"
pass "Wi-Fi QR preview uses dedicated floating window rules"

created_uuid="$tmp/created-uuid"
deleted_uuid="$tmp/deleted-uuid"
edit_input="$tmp/edit-input"

run_connect() {
  local security=$1 hidden=$2 ssid=$3 password=$4

  : >"$calls"
  rm -f "$created_uuid" "$deleted_uuid" "$edit_input"
  printf '%s' "$password" | TEST_CALLS="$calls" TEST_CREATED_UUID="$created_uuid" \
    TEST_DELETED_UUID="$deleted_uuid" TEST_EDIT_INPUT="$edit_input" PATH="$tmp/bin:$PATH" \
    "$connect" "$security" "$hidden" "$ssid"
}

run_connect nopass false "Open Cafe" ""
open_calls=$(<"$calls")
[[ $open_calls == *$'nmcli\tconnection\tadd\ttype\twifi\tifname\t*\tcon-name\tOpen Cafe\tconnection.uuid\t'*$'\tssid\tOpen Cafe'* ]] ||
  fail "QR connection helper creates an open Wi-Fi profile" "$open_calls"
[[ $open_calls == *$'nmcli\tconnection\tmodify\tuuid\t'*$'\t802-11-wireless.hidden\tno'* ]] ||
  fail "QR connection helper configures a visible open network" "$open_calls"
[[ $open_calls != *802-11-wireless-security* && ! -e $edit_input ]] || fail "QR connection helper leaves open profiles unsecured" "$open_calls"
[[ $open_calls == *$'nmcli\tconnection\tup\tuuid\t'* ]] || fail "QR connection helper activates an open profile" "$open_calls"
pass "QR connection helper configures open Wi-Fi"

wpa_password='wpa "secret" \ never in argv'
run_connect WPA true "Private Cafe" "$wpa_password"
wpa_calls=$(<"$calls")
[[ $wpa_calls == *$'802-11-wireless.hidden\tyes'* && $wpa_calls == *$'802-11-wireless-security.key-mgmt\twpa-psk'* ]] ||
  fail "QR connection helper configures hidden WPA/WPA2 Wi-Fi" "$wpa_calls"
[[ $(<"$edit_input") == $'set 802-11-wireless-security.psk "wpa \\"secret\\" \\\\ never in argv"\nsave\nquit' ]] ||
  fail "QR connection helper supplies the WPA password through editor stdin" "$(<"$edit_input")"
[[ $wpa_calls != *"$wpa_password"* ]] || fail "QR connection helper keeps the WPA password out of process arguments" "$wpa_calls"
pass "QR connection helper configures WPA/WPA2 without password arguments"

sae_password='sae secret never in argv'
run_connect SAE false "WPA3 Cafe" "$sae_password"
sae_calls=$(<"$calls")
[[ $sae_calls == *$'802-11-wireless-security.key-mgmt\tsae'* ]] || fail "QR connection helper configures WPA3/SAE" "$sae_calls"
[[ $(<"$edit_input") == *"$sae_password"* && $sae_calls != *"$sae_password"* ]] ||
  fail "QR connection helper sends the SAE password only through stdin" "$sae_calls"
pass "QR connection helper configures WPA3/SAE without password arguments"

wep_password='wep-secret-never-in-argv'
run_connect WEP no "Legacy Cafe" "$wep_password"
wep_calls=$(<"$calls")
[[ $wep_calls == *$'802-11-wireless-security.key-mgmt\tnone'* ]] || fail "QR connection helper configures WEP key management" "$wep_calls"
[[ $wep_calls == *$'802-11-wireless-security.wep-key-type\t1'* ]] || fail "QR connection helper preserves a raw WEP key" "$wep_calls"
[[ $(<"$edit_input") == $'set 802-11-wireless-security.wep-key0 "wep-secret-never-in-argv"\nsave\nquit' ]] ||
  fail "QR connection helper supplies the WEP key through editor stdin" "$(<"$edit_input")"
[[ $wep_calls != *"$wep_password"* ]] || fail "QR connection helper keeps the WEP key out of process arguments" "$wep_calls"
pass "QR connection helper configures WEP without password arguments"

: >"$calls"
if printf 'enterprise-secret' | TEST_CALLS="$calls" TEST_CREATED_UUID="$created_uuid" TEST_DELETED_UUID="$deleted_uuid" \
  TEST_EDIT_INPUT="$edit_input" PATH="$tmp/bin:$PATH" "$connect" EAP false Enterprise >"$tmp/out" 2>"$tmp/error"; then
  fail "QR connection helper rejects unsupported security types"
fi
[[ $(<"$tmp/error") == "Unsupported Wi-Fi security type: EAP" ]] || fail "QR connection helper explains unsupported security types" "$(<"$tmp/error")"
[[ ! -s $calls ]] || fail "QR connection helper rejects unsupported security before creating a profile" "$(<"$calls")"
pass "QR connection helper rejects unsupported security types"

: >"$calls"
rm -f "$created_uuid" "$deleted_uuid" "$edit_input"
if printf 'cleanup-secret' | TEST_NMCLI_FAIL_ON=up TEST_CALLS="$calls" TEST_CREATED_UUID="$created_uuid" \
  TEST_DELETED_UUID="$deleted_uuid" TEST_EDIT_INPUT="$edit_input" PATH="$tmp/bin:$PATH" \
  "$connect" WPA false Cleanup >"$tmp/out" 2>"$tmp/error"; then
  fail "QR connection helper reports activation failure"
fi
[[ -s $created_uuid && -s $deleted_uuid && $(<"$created_uuid") == "$(<"$deleted_uuid")" ]] ||
  fail "QR connection helper deletes the exact profile after activation failure" "$(<"$calls")"
[[ $(<"$calls") != *cleanup-secret* ]] || fail "QR connection helper keeps failed passwords out of process arguments" "$(<"$calls")"
pass "QR connection helper deletes its profile on failure"

: >"$calls"
rm -f "$created_uuid" "$deleted_uuid" "$edit_input"
up_ready="$tmp/up-ready"
up_stopped="$tmp/up-stopped"
printf 'cancel-secret\n' | TEST_UP_READY="$up_ready" TEST_UP_STOPPED="$up_stopped" TEST_CALLS="$calls" \
  TEST_CREATED_UUID="$created_uuid" TEST_DELETED_UUID="$deleted_uuid" TEST_EDIT_INPUT="$edit_input" \
  PATH="$tmp/bin:$PATH" "$connect" WPA false Cancelled >"$tmp/out" 2>"$tmp/error" &
connect_pid=$!
for _ in {1..100}; do [[ -e $up_ready ]] && break; sleep 0.01; done
[[ -e $up_ready ]] || fail "QR connection helper reaches activation for cancellation coverage"
kill "$connect_pid"
wait "$connect_pid" 2>/dev/null || true
[[ -e $up_stopped ]] || fail "QR connection helper terminates the active NetworkManager request"
[[ -s $created_uuid && -s $deleted_uuid && $(<"$created_uuid") == "$(<"$deleted_uuid")" ]] ||
  fail "QR connection helper deletes its profile after cancellation" "$(<"$calls")"
pass "QR connection helper terminates activation and cleans up when canceled"

: >"$calls"
rm -f "$edit_input"
printf 'safe\nsave\nquit' | TEST_CALLS="$calls" TEST_CREATED_UUID="$created_uuid" TEST_DELETED_UUID="$deleted_uuid" \
  TEST_EDIT_INPUT="$edit_input" PATH="$tmp/bin:$PATH" "$connect" WPA false Injection
[[ $(<"$edit_input") == $'set 802-11-wireless-security.psk "safe"\nsave\nquit' ]] ||
  fail "QR connection helper confines stdin to one password line" "$(<"$edit_input")"
pass "QR connection helper confines stdin to one password line"
