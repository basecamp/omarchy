#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

command="$ROOT/bin/omarchy-bluetooth-reconnect"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mouse="AA:AA:AA:AA:AA:AA"
keyboard="BB:BB:BB:BB:BB:BB"
headset="CC:CC:CC:CC:CC:CC"
hid_uuid="00001124-0000-1000-8000-00805f9b34fb"
a2dp_uuid="0000110b-0000-1000-8000-00805f9b34fb"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/bluetoothctl" <<'EOF'
#!/bin/bash

state=$BLUETOOTHCTL_STATE

case "$1" in
  show)
    echo "Controller 00:00:00:00:00:00 (public)"
    echo "  Powered: $(<"$state/powered")"
    ;;
  devices)
    cat "$state/devices"
    ;;
  info)
    cat "$state/info/$2"
    ;;
  connect)
    echo "$2" >>"$state/connect-log"

    if [[ -f $state/fail-$2 ]]; then
      remaining=$(<"$state/fail-$2")
      if ((remaining > 0)); then
        echo $((remaining - 1)) >"$state/fail-$2"
        exit 1
      fi
    fi

    echo "Connection successful"
    ;;
esac
EOF
chmod +x "$tmp/bin/bluetoothctl"

# A trusted device as bluetoothctl describes it: the UUID lines are what
# separates a keyboard from a headset, and Connected is what makes it a
# candidate.
describe_device() {
  local address=$1 name=$2 uuid=$3 connected=$4

  mkdir -p "$tmp/state/info"
  cat >"$tmp/state/info/$address" <<EOF
Device $address ($name)
	Name: $name
	Paired: yes
	Trusted: yes
	Connected: $connected
	UUID: Vendor specific           ($uuid)
EOF
}

reset_state() {
  rm -rf "$tmp/state"
  mkdir -p "$tmp/state/info"
  echo yes >"$tmp/state/powered"
  : >"$tmp/state/devices"
  : >"$tmp/state/connect-log"
}

trust_device() {
  echo "Device $1 $2" >>"$tmp/state/devices"
}

run_reconnect() {
  BLUETOOTHCTL_STATE="$tmp/state" \
    OMARCHY_BLUETOOTH_RECONNECT_WAIT_SECONDS=0 \
    OMARCHY_BLUETOOTH_RECONNECT_RETRY_SECONDS=0 \
    PATH="$tmp/bin:$ROOT/bin:$PATH" \
    "$command" 2>"$tmp/err"
}

connect_log() {
  tr '\n' ' ' <"$tmp/state/connect-log" | sed 's/ $//'
}

# A trusted keyboard and mouse left disconnected are exactly what BlueZ will not
# pick up on its own, so both must be asked for.
reset_state
describe_device "$mouse" "Magic Mouse" "$hid_uuid" no
describe_device "$keyboard" "Magic Keyboard" "$hid_uuid" no
trust_device "$mouse" "Magic Mouse"
trust_device "$keyboard" "Magic Keyboard"
run_reconnect
[[ $(connect_log) == "$mouse $keyboard" ]] ||
  fail "reconnect connects trusted keyboards and mice" "actual: $(connect_log)"
pass "reconnect connects trusted keyboards and mice"

# Audio is already covered by ReconnectUUIDs and wireplumber, and grabbing a
# headset at login would move audio off the speakers uninvited.
reset_state
describe_device "$headset" "Headset" "$a2dp_uuid" no
trust_device "$headset" "Headset"
run_reconnect
[[ -z $(connect_log) ]] ||
  fail "reconnect leaves non-HID devices alone" "actual: $(connect_log)"
pass "reconnect leaves non-HID devices alone"

# Asking for a device that is already connected would be a no-op at best, and
# BlueZ has been known to drop and re-establish the link at worst.
reset_state
describe_device "$mouse" "Magic Mouse" "$hid_uuid" yes
trust_device "$mouse" "Magic Mouse"
run_reconnect
[[ -z $(connect_log) ]] ||
  fail "reconnect skips devices already connected" "actual: $(connect_log)"
pass "reconnect skips devices already connected"

# Bluetooth being off is a decision the rfkill soft block carries across reboots.
# Reconnecting must not be what turns it back on.
reset_state
echo no >"$tmp/state/powered"
describe_device "$mouse" "Magic Mouse" "$hid_uuid" no
trust_device "$mouse" "Magic Mouse"
run_reconnect
[[ -z $(connect_log) ]] ||
  fail "reconnect does nothing while the adapter is unpowered" "actual: $(connect_log)"
pass "reconnect does nothing while the adapter is unpowered"

# A peripheral woken by the same power-on as the machine can miss the first
# attempt while its own radio is still coming up.
reset_state
describe_device "$mouse" "Magic Mouse" "$hid_uuid" no
trust_device "$mouse" "Magic Mouse"
echo 2 >"$tmp/state/fail-$mouse"
run_reconnect
[[ $(connect_log) == "$mouse $mouse $mouse" ]] ||
  fail "reconnect retries a device that does not answer at once" "actual: $(connect_log)"
[[ -z $(<"$tmp/err") ]] ||
  fail "reconnect stays quiet once a retry succeeds" "actual: $(<"$tmp/err")"
pass "reconnect retries a device that does not answer at once"

# Giving up silently would leave nothing to explain a dead keyboard.
reset_state
describe_device "$keyboard" "Magic Keyboard" "$hid_uuid" no
trust_device "$keyboard" "Magic Keyboard"
echo 99 >"$tmp/state/fail-$keyboard"
run_reconnect
[[ $(<"$tmp/err") == *"$keyboard did not connect"* ]] ||
  fail "reconnect reports a device it could not connect" "actual: $(<"$tmp/err")"
pass "reconnect reports a device it could not connect"

service="$ROOT/default/systemd/user/omarchy-bluetooth-reconnect.service"
grep -Fx 'ExecStart=/usr/bin/omarchy-bluetooth-reconnect' "$service" >/dev/null
grep -Fx 'ExecCondition=/usr/bin/systemctl is-active --quiet bluetooth.service' "$service" >/dev/null ||
  fail "reconnect spends the adapter wait on machines where bluetoothd never runs"
grep -Fx 'WantedBy=graphical-session.target' "$service" >/dev/null ||
  fail "reconnect is never pulled in at login without a WantedBy"
grep -Fx 'After=graphical-session.target' "$service" >/dev/null ||
  fail "a oneshot that waits for the adapter can hold graphical-session.target open"
pass "reconnect runs once per login after the graphical session is ready"

first_run_units="$ROOT/install/user/first-run/enable-user-units.sh"
grep -F 'omarchy-bluetooth-reconnect.service' "$first_run_units" >/dev/null ||
  fail "first-run does not enable the reconnect unit, so new installs never get it"
pass "first-run enables the reconnect unit"

# The unit has to be installed by the package before anything can enable it by
# name: first-run enables every unit in one command under `set -e`, so a unit
# missing from /usr/lib/systemd/user takes bt-agent and the sleep lock down with
# it. config-test.sh holds the PKGBUILD mapping that keeps that honest.
grep -F 'default/systemd/user/omarchy-bluetooth-reconnect.service' "$ROOT/test/shell.d/config-test.sh" >/dev/null ||
  fail "reconnect unit is enabled by name with no PKGBUILD coverage asserting the package installs it"
pass "reconnect unit is covered by the PKGBUILD mapping"

migration="$ROOT/migrations/1787330669.sh"
grep -F 'systemctl --user enable omarchy-bluetooth-reconnect.service' "$migration" >/dev/null ||
  fail "migration must enable without --now; --now starts the unit before the session-gate check"
grep -F 'graphical-session.target.wants' "$migration" >/dev/null ||
  fail "an update over SSH has no user manager to enable into, so the migration completes with the unit unenabled and no second chance"
grep -F 'is-active --quiet graphical-session.target' "$migration" >/dev/null ||
  fail "migration reaches for the peripherals of whoever is at the machine during an update from a TTY"
pass "migration enables for existing installs with or without a live user manager"
