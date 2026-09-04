#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# network-test.sh only regex-matches the generated bash source of these two
# scripts. This file actually runs them against stubbed nmcli/uuidgen so the
# lifecycle (dedupe, EXIT trap, autoconnect arm order) is proven, not just
# grepped for.

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

psk_script=$(node -e 'process.stdout.write(require(process.argv[1]).hiddenPskConnectScript)' "$ROOT/shell/plugins/panels/network/Model.js")
open_script=$(node -e 'process.stdout.write(require(process.argv[1]).hiddenOpenConnectScript)' "$ROOT/shell/plugins/panels/network/Model.js")

cat >"$tmp/bin/uuidgen" <<'EOF'
#!/bin/bash
echo new-uuid-0000
EOF
chmod +x "$tmp/bin/uuidgen"

# Logs the full argv of every nmcli call (one line per call) and dispatches on
# argv substrings, so assertions can grep the log for what actually ran and in
# what order, instead of trusting the script's own source text.
cat >"$tmp/bin/nmcli" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$NM_CALL_LOG"
case "$*" in
  *"connection add"*)
    exit 0
    ;;
  *"connection edit"*)
    cat >"$NM_EDIT_INPUT"
    exit 0
    ;;
  *"connection up"*)
    # Mirrors real nmcli's SIGTERM handling so termination coverage exercises
    # the panel's kill actually reaching this process, not just the parent
    # bash -c wrapper around it. The sleep itself is backgrounded (rather
    # than run as a foreground child of this trap-bearing script) so this
    # stub reacts to TERM immediately, the way a real, single-process nmcli
    # would -- a foreground sleep here would reintroduce the exact
    # defer-until-child-returns bug this stub exists to catch, just one
    # process further down.
    [[ -n ${NM_UP_PID_FILE:-} ]] && printf '%s\n' "$$" >"$NM_UP_PID_FILE"
    if [[ -n ${NM_UP_SLEEP:-} ]]; then
      sleep "$NM_UP_SLEEP" & sleep_pid=$!
      trap 'kill -TERM $sleep_pid 2>/dev/null; exit 143' TERM
      wait $sleep_pid
    fi
    exit "${NM_UP_RC:-0}"
    ;;
  *"connection modify"*)
    exit "${NM_MODIFY_RC:-0}"
    ;;
  *"connection delete"*)
    exit 0
    ;;
  *"-t -f UUID,TYPE connection show"*)
    [[ -n ${NM_LIST_PID_FILE:-} ]] && printf '%s\n' "$$" >"$NM_LIST_PID_FILE"
    if [[ -n ${NM_LIST_SLEEP:-} ]]; then
      sleep "$NM_LIST_SLEEP" & sleep_pid=$!
      trap 'kill -TERM $sleep_pid 2>/dev/null; exit 143' TERM
      wait $sleep_pid
    fi
    printf '%s' "$NM_CONNECTIONS"
    ;;
  *"--escape no -g"*)
    printf '%s' "$NM_WIFI_FIELDS"
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$tmp/bin/nmcli"

# Builds one dedupe record: 15 `nmcli -g` fields in the exact order the
# dedupe reads them, plus the blank line separating it from the next record.
# Keeping this as a function (rather than inline heredocs per scenario) is
# what makes it tractable to add a distinctly-customized record per test
# without each one silently drifting out of field-count alignment.
wifi_record() {
  local uuid=$1 ssid=$2 hidden=$3 keymgmt=$4 bssid=$5 mac=$6 iface=$7
  local ip4m=$8 ip6m=$9 ip4addr=${10} ip4dns=${11} ip4routes=${12}
  local ip6addr=${13} ip6dns=${14} ip6routes=${15}
  printf '%s\n' "$uuid" "$ssid" "$hidden" "$keymgmt" "$bssid" "$mac" "$iface" \
    "$ip4m" "$ip6m" "$ip4addr" "$ip4dns" "$ip4routes" "$ip6addr" "$ip6dns" "$ip6routes" ""
}

# Three saved connections: a prior hidden profile for the SSID under test (the
# one dedupe should remove), a broadcast profile with the same SSID (dedupe
# must leave it alone -- it is not hidden), and an unrelated ethernet profile
# (dedupe must not even consider non-wifi types). The SSID carries a space to
# prove the scripts stay space-safe end to end.
NM_CONNECTIONS=$'old-hidden:802-11-wireless\nbroadcast:802-11-wireless\neth:802-3-ethernet\nnew-uuid-0000:802-11-wireless\n'
NM_WIFI_FIELDS_PSK=$(
  wifi_record old-hidden "my ssid" yes wpa-psk "" "" "" auto auto "" "" "" "" "" ""
  wifi_record broadcast "my ssid" no "" "" "" "" auto auto "" "" "" "" "" ""
  wifi_record new-uuid-0000 "my ssid" yes wpa-psk "" "" "" auto auto "" "" "" "" "" ""
)
NM_WIFI_FIELDS_OPEN=$(
  wifi_record old-hidden "my ssid" yes "" "" "" "" auto auto "" "" "" "" "" ""
  wifi_record broadcast "my ssid" no "" "" "" "" auto auto "" "" "" "" "" ""
  wifi_record new-uuid-0000 "my ssid" yes "" "" "" "" auto auto "" "" "" "" "" ""
)

assert_contains() {
  local file=$1 needle=$2 description=$3

  grep -qF -- "$needle" "$file" || fail "$description" "expected '$file' to contain: $needle\nactual:\n$(cat "$file" 2>/dev/null)"
  pass "$description"
}

assert_not_contains() {
  local file=$1 needle=$2 description=$3

  if [[ -f $file ]] && grep -qF -- "$needle" "$file"; then
    fail "$description" "expected '$file' to NOT contain: $needle\nactual:\n$(cat "$file")"
  fi
  pass "$description"
}

# Proves ordering, not just presence -- a dedupe delete that ran before
# connection up would delete the old profile before the new one is proven.
assert_order() {
  local file=$1 first=$2 second=$3 description=$4
  local first_line second_line

  first_line=$(grep -n -m1 -F -- "$first" "$file" | cut -d: -f1 || true)
  second_line=$(grep -n -m1 -F -- "$second" "$file" | cut -d: -f1 || true)
  if [[ -z $first_line || -z $second_line ]] || (( first_line >= second_line )); then
    fail "$description" "first='$first' at line ${first_line:-none}; second='$second' at line ${second_line:-none}\n$(cat -n "$file")"
  fi
  pass "$description"
}

# --- Scenario 1: PSK success ---------------------------------------------

log=$tmp/log_psk_success
edit=$tmp/edit_psk_success
: >"$log"

rc=0
printf 'secret pass\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_PSK" \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk || rc=$?
(( rc == 0 )) || fail "hidden PSK connect succeeds when activation and autoconnect arm both succeed" "exit code: $rc"
pass "hidden PSK connect succeeds when activation and autoconnect arm both succeed"

add_line=$(grep -m1 -F "connection add" "$log") || true
[[ $add_line == *"connection.autoconnect no"* ]] || fail "hidden PSK success creates the profile inert (autoconnect no)" "$add_line"
pass "hidden PSK success creates the profile inert (autoconnect no)"
[[ $add_line == *"802-11-wireless.hidden yes"* ]] || fail "hidden PSK success marks the new profile hidden" "$add_line"
pass "hidden PSK success marks the new profile hidden"
[[ $add_line == *"wifi-sec.key-mgmt wpa-psk"* ]] || fail "hidden PSK success sets key-mgmt from the caller argument" "$add_line"
pass "hidden PSK success sets key-mgmt from the caller argument"
[[ $add_line == *"my ssid"* ]] || fail "hidden PSK success creates the profile with the requested ssid" "$add_line"
pass "hidden PSK success creates the profile with the requested ssid"

assert_contains "$edit" "set wifi-sec.psk secret pass" "hidden PSK success sets the passphrase through the connection editor's stdin"

# The passphrase must never appear in any nmcli argv line -- argv is world
# readable in /proc, so a leak here is a local secret-disclosure bug.
assert_not_contains "$log" "secret pass" "hidden PSK success never puts the passphrase in nmcli argv"

delete_line=$(grep -m1 -F "connection delete" "$log") || true
[[ $delete_line == *"uuid old-hidden"* ]] || fail "hidden PSK success deletes an uncustomized prior hidden profile for this ssid" "$delete_line"
pass "hidden PSK success deletes an uncustomized prior hidden profile for this ssid"
[[ $delete_line != *"broadcast"* ]] || fail "hidden PSK success never deletes a same-ssid broadcast profile" "$delete_line"
pass "hidden PSK success never deletes a same-ssid broadcast profile"
[[ $delete_line != *"eth"* ]] || fail "hidden PSK success never deletes an unrelated ethernet profile" "$delete_line"
pass "hidden PSK success never deletes an unrelated ethernet profile"
[[ $delete_line != *"new-uuid-0000"* ]] || fail "hidden PSK success never deletes the profile it just activated (self-exclusion)" "$delete_line"
pass "hidden PSK success never deletes the profile it just activated (self-exclusion)"

assert_order "$log" "connection up" "connection modify" "hidden PSK success brings the profile up before arming autoconnect"
assert_order "$log" "connection modify" "connection delete" "hidden PSK success arms autoconnect before deleting the old profile"
assert_order "$log" "connection modify" "-t -f UUID,TYPE" "hidden PSK success runs the whole snapshot, both queries, only after the autoconnect arm"
assert_order "$log" "connection modify" "--escape no -g" "hidden PSK success snapshots duplicates only after the autoconnect arm, adjacent to the delete"
assert_order "$log" "--escape no -g" "connection delete" "hidden PSK success deletes from the fresh snapshot, not a stale pre-connect one"

# --- Scenario 2: PSK activation failure ----------------------------------

log=$tmp/log_psk_up_fail
edit=$tmp/edit_psk_up_fail
: >"$log"

rc=0
printf 'secret pass\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_PSK" \
  NM_UP_RC=1 \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk || rc=$?
(( rc != 0 )) || fail "hidden PSK connect fails when activation fails"
pass "hidden PSK connect fails when activation fails"

assert_contains "$log" "connection delete uuid new-uuid-0000" "hidden PSK activation failure lets the EXIT trap delete the unproven profile"
assert_not_contains "$log" "delete uuid old-hidden" "hidden PSK activation failure leaves the old profile in place"
assert_not_contains "$log" "autoconnect yes" "hidden PSK activation failure never arms autoconnect"

# --- Scenario 3: PSK autoconnect-arm failure ------------------------------

log=$tmp/log_psk_modify_fail
edit=$tmp/edit_psk_modify_fail
: >"$log"

rc=0
printf 'secret pass\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_PSK" \
  NM_MODIFY_RC=1 \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk || rc=$?
# Success is pinned to activation, not to the autoconnect arm -- the
# connection really is up, so the overall attempt must report success even
# though the arm step failed.
(( rc == 0 )) || fail "hidden PSK connect still succeeds when only the autoconnect arm fails" "exit code: $rc"
pass "hidden PSK connect still succeeds when only the autoconnect arm fails"

assert_not_contains "$log" "delete uuid old-hidden" "hidden PSK arm failure keeps the old, still-autoconnecting profile"
assert_not_contains "$log" "delete uuid new-uuid-0000" "hidden PSK arm failure keeps the newly-activated profile"

# --- Scenario 4: PSK termination ------------------------------------------
#
# NM_UP_SLEEP is long (20s) and the assertions require the script to exit and
# the stubbed nmcli child to die within a couple of seconds of SIGTERM -- if
# the panel's kill only reached the parent `bash -c` (the pre-fix behavior),
# this would block for the full sleep instead.

log=$tmp/log_psk_term
edit=$tmp/edit_psk_term
input=$tmp/input_psk_term
pidfile=$tmp/pid_psk_term
: >"$log"
rm -f "$pidfile"
printf 'secret pass\n' >"$input"

PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_PSK" \
  NM_UP_SLEEP=20 NM_UP_PID_FILE="$pidfile" \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk <"$input" &
pid=$!

waited=0
while [[ ! -s $pidfile ]]; do
  sleep 0.1
  waited=$((waited + 1))
  (( waited < 50 )) || fail "hidden PSK termination test setup" "nmcli stub pid file never appeared within 5s"
done
nmcli_pid=$(<"$pidfile")

start_ns=$(date +%s%N)
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))

(( elapsed_ms < 2000 )) || fail "hidden PSK termination reaches the child nmcli process instead of waiting for it to exit on its own" "elapsed: ${elapsed_ms}ms"
pass "hidden PSK termination reaches the child nmcli process instead of waiting for it to exit on its own"

(( rc != 0 )) || fail "hidden PSK connect reports failure when killed mid-activation"
pass "hidden PSK connect reports failure when killed mid-activation"

sleep 0.3
if kill -0 "$nmcli_pid" 2>/dev/null; then
  fail "hidden PSK termination terminates the child nmcli process rather than orphaning it" "pid $nmcli_pid is still running"
fi
pass "hidden PSK termination terminates the child nmcli process rather than orphaning it"

assert_contains "$log" "connection delete uuid new-uuid-0000" "hidden PSK termination lets the EXIT trap delete the unproven profile"
assert_not_contains "$log" "delete uuid old-hidden" "hidden PSK termination leaves the old profile in place"

# --- Scenario 4b: PSK termination during the post-activation snapshot -----
#
# Mirrors scenario 4, but hangs the dedupe's `-t -f UUID,TYPE` query instead
# of `connection up`. The snapshot now runs inside the modify-success block,
# after the profile is created and activated -- this proves the re-armed TERM
# trap still reaches the process substitution's nmcli at that later point,
# and that a kill there leaves the already-activated connection and every
# duplicate alone (nothing left to delete yet).

log=$tmp/log_psk_list_term
edit=$tmp/edit_psk_list_term
input=$tmp/input_psk_list_term
pidfile=$tmp/pid_list_term
: >"$log"
rm -f "$pidfile"
printf 'secret pass\n' >"$input"

PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_PSK" \
  NM_LIST_SLEEP=20 NM_LIST_PID_FILE="$pidfile" \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk <"$input" &
pid=$!

waited=0
while [[ ! -s $pidfile ]]; do
  sleep 0.1
  waited=$((waited + 1))
  (( waited < 50 )) || fail "hidden PSK post-activation snapshot termination test setup" "nmcli stub pid file never appeared within 5s"
done
nmcli_pid=$(<"$pidfile")

start_ns=$(date +%s%N)
kill -TERM "$pid"
rc=0
wait "$pid" || rc=$?
elapsed_ms=$(( ($(date +%s%N) - start_ns) / 1000000 ))

(( elapsed_ms < 2000 )) || fail "hidden PSK post-activation snapshot termination interrupts the trap-armed read instead of waiting out the query" "elapsed: ${elapsed_ms}ms"
pass "hidden PSK post-activation snapshot termination interrupts the trap-armed read instead of waiting out the query"

(( rc != 0 )) || fail "hidden PSK connect reports failure when killed during the post-activation snapshot"
pass "hidden PSK connect reports failure when killed during the post-activation snapshot"

sleep 0.3
if kill -0 "$nmcli_pid" 2>/dev/null; then
  fail "hidden PSK post-activation snapshot termination kills the query's nmcli rather than orphaning it" "pid $nmcli_pid is still running"
fi
pass "hidden PSK post-activation snapshot termination kills the query's nmcli rather than orphaning it"

assert_contains "$log" "connection add" "hidden PSK snapshot-phase termination happens after the profile was created"
assert_contains "$log" "connection up" "hidden PSK snapshot-phase termination happens after activation"
assert_not_contains "$log" "connection delete" "hidden PSK snapshot-phase termination deletes nothing: the activated profile survives and duplicates are left alone"

# --- Scenario 5: dedupe preserves customized same-SSID hidden profiles ----
#
# Each of these profiles matches on SSID/hidden/key-mgmt alone -- the same
# fields the pre-fix dedupe checked -- but differs on one customization the
# fixed dedupe must also check. old-hidden is included alongside them purely
# as the still-must-be-deleted control from scenario 1/3.

log=$tmp/log_psk_customized
edit=$tmp/edit_psk_customized
: >"$log"

NM_CONNECTIONS_CUSTOM=$'old-hidden:802-11-wireless\ncustom-ip4method:802-11-wireless\ncustom-ip4dns:802-11-wireless\ncustom-iface:802-11-wireless\neth:802-3-ethernet\n'
NM_WIFI_FIELDS_CUSTOM=$(
  wifi_record old-hidden "my ssid" yes wpa-psk "" "" "" auto auto "" "" "" "" "" ""
  wifi_record custom-ip4method "my ssid" yes wpa-psk "" "" "" manual auto "" "" "" "" "" ""
  wifi_record custom-ip4dns "my ssid" yes wpa-psk "" "" "" auto auto "" "8.8.8.8" "" "" "" ""
  wifi_record custom-iface "my ssid" yes wpa-psk "" "" wlan0 auto auto "" "" "" "" "" ""
)

rc=0
printf 'secret pass\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS_CUSTOM" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_CUSTOM" \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk || rc=$?
(( rc == 0 )) || fail "hidden PSK connect succeeds alongside customized same-ssid profiles" "exit code: $rc"
pass "hidden PSK connect succeeds alongside customized same-ssid profiles"

delete_line=$(grep -m1 -F "connection delete" "$log") || true
[[ $delete_line == *"uuid old-hidden"* ]] || fail "hidden PSK dedupe still deletes the uncustomized duplicate" "$delete_line"
pass "hidden PSK dedupe still deletes the uncustomized duplicate"
[[ $delete_line != *"custom-ip4method"* ]] || fail "hidden PSK dedupe spares a same-ssid profile with a manual ipv4.method" "$delete_line"
pass "hidden PSK dedupe spares a same-ssid profile with a manual ipv4.method"
[[ $delete_line != *"custom-ip4dns"* ]] || fail "hidden PSK dedupe spares a same-ssid profile with a custom ipv4.dns" "$delete_line"
pass "hidden PSK dedupe spares a same-ssid profile with a custom ipv4.dns"
[[ $delete_line != *"custom-iface"* ]] || fail "hidden PSK dedupe spares a same-ssid profile bound to an interface" "$delete_line"
pass "hidden PSK dedupe spares a same-ssid profile bound to an interface"

# --- Scenario 6: dedupe preserves a same-SSID profile with different key-mgmt

log=$tmp/log_psk_keymgmt
edit=$tmp/edit_psk_keymgmt
: >"$log"

NM_CONNECTIONS_KEYMGMT=$'old-hidden:802-11-wireless\ncustom-keymgmt:802-11-wireless\neth:802-3-ethernet\n'
NM_WIFI_FIELDS_KEYMGMT=$(
  wifi_record old-hidden "my ssid" yes wpa-psk "" "" "" auto auto "" "" "" "" "" ""
  wifi_record custom-keymgmt "my ssid" yes sae "" "" "" auto auto "" "" "" "" "" ""
)

rc=0
printf 'secret pass\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$edit" \
  NM_CONNECTIONS="$NM_CONNECTIONS_KEYMGMT" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_KEYMGMT" \
  bash -c "$psk_script" nmcli-hidden-psk "my ssid" wpa-psk || rc=$?
(( rc == 0 )) || fail "hidden PSK connect succeeds alongside a same-ssid sae profile" "exit code: $rc"
pass "hidden PSK connect succeeds alongside a same-ssid sae profile"

delete_line=$(grep -m1 -F "connection delete" "$log") || true
[[ $delete_line == *"uuid old-hidden"* ]] || fail "hidden PSK dedupe still deletes the same-key-mgmt duplicate" "$delete_line"
pass "hidden PSK dedupe still deletes the same-key-mgmt duplicate"
[[ $delete_line != *"custom-keymgmt"* ]] || fail "hidden PSK dedupe spares a same-ssid profile using a different key-mgmt (sae vs wpa-psk)" "$delete_line"
pass "hidden PSK dedupe spares a same-ssid profile using a different key-mgmt (sae vs wpa-psk)"

# --- Scenario 7: Open network success -------------------------------------

log=$tmp/log_open_success
: >"$log"

rc=0
printf '\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$tmp/edit_open_success" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_OPEN" \
  bash -c "$open_script" nmcli-hidden-open "my ssid" || rc=$?
(( rc == 0 )) || fail "hidden open connect succeeds when activation and autoconnect arm both succeed" "exit code: $rc"
pass "hidden open connect succeeds when activation and autoconnect arm both succeed"

add_line=$(grep -m1 -F "connection add" "$log") || true
[[ $add_line == *"802-11-wireless.hidden yes"* ]] || fail "hidden open success marks the new profile hidden" "$add_line"
pass "hidden open success marks the new profile hidden"
[[ $add_line == *"connection.autoconnect no"* ]] || fail "hidden open success creates the profile inert (autoconnect no)" "$add_line"
pass "hidden open success creates the profile inert (autoconnect no)"

assert_not_contains "$log" "wifi-sec" "hidden open success sets no wifi security properties on an open profile"
assert_not_contains "$log" "connection edit" "hidden open success never opens the connection editor, since there is no secret to set"

delete_line=$(grep -m1 -F "connection delete" "$log") || true
[[ $delete_line == *"uuid old-hidden"* ]] || fail "hidden open success deletes the prior hidden profile for this ssid" "$delete_line"
pass "hidden open success deletes the prior hidden profile for this ssid"
[[ $delete_line != *"broadcast"* ]] || fail "hidden open success never deletes a same-ssid broadcast profile" "$delete_line"
pass "hidden open success never deletes a same-ssid broadcast profile"
[[ $delete_line != *"eth"* ]] || fail "hidden open success never deletes an unrelated ethernet profile" "$delete_line"
pass "hidden open success never deletes an unrelated ethernet profile"
[[ $delete_line != *"new-uuid-0000"* ]] || fail "hidden open success never deletes the profile it just activated (self-exclusion)" "$delete_line"
pass "hidden open success never deletes the profile it just activated (self-exclusion)"

assert_order "$log" "connection up" "connection modify" "hidden open success brings the profile up before arming autoconnect"
assert_order "$log" "connection modify" "connection delete" "hidden open success arms autoconnect before deleting the old profile"
assert_order "$log" "connection modify" "-t -f UUID,TYPE" "hidden open success runs the whole snapshot, both queries, only after the autoconnect arm"
assert_order "$log" "connection modify" "--escape no -g" "hidden open success snapshots duplicates only after the autoconnect arm, adjacent to the delete"
assert_order "$log" "--escape no -g" "connection delete" "hidden open success deletes from the fresh snapshot, not a stale pre-connect one"

# --- Scenario 8: Open network activation failure --------------------------

log=$tmp/log_open_up_fail
: >"$log"

rc=0
printf '\n' | PATH="$tmp/bin:$PATH" \
  NM_CALL_LOG="$log" NM_EDIT_INPUT="$tmp/edit_open_up_fail" \
  NM_CONNECTIONS="$NM_CONNECTIONS" NM_WIFI_FIELDS="$NM_WIFI_FIELDS_OPEN" \
  NM_UP_RC=1 \
  bash -c "$open_script" nmcli-hidden-open "my ssid" || rc=$?
(( rc != 0 )) || fail "hidden open connect fails when activation fails"
pass "hidden open connect fails when activation fails"

assert_contains "$log" "connection delete uuid new-uuid-0000" "hidden open activation failure lets the EXIT trap delete the unproven profile"
assert_not_contains "$log" "delete uuid old-hidden" "hidden open activation failure leaves the old profile in place"
