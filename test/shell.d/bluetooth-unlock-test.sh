#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

controller="00:11:22:33:44:55"
device="AA:BB:CC:DD:EE:FF"
mkdir -p \
  "$test_dir/bin" \
  "$test_dir/state/$controller/$device" \
  "$test_dir/etc/omarchy" \
  "$test_dir/etc/mkinitcpio.conf.d" \
  "$test_dir/usr/lib/initcpio/install" \
  "$test_dir/usr/lib/initcpio/hooks"
printf '[General]\nName=Test keyboard\nClass=0x002540\nTrusted=true\n[LinkKey]\nKey=00000000000000000000000000000000\n' >"$test_dir/state/$controller/$device/info"
printf 'HOOKS=(base udev keyboard encrypt filesystems)\n' >"$test_dir/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

cat >"$test_dir/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF

cat >"$test_dir/bin/bluetoothctl" <<'EOF'
#!/bin/bash
# An explicit controller/device pair lets the ISO configure the target after
# copying its live BlueZ bond, before the target's D-Bus is running.
exit 0
EOF

cat >"$test_dir/bin/omarchy-cmd-missing" <<'EOF'
#!/bin/bash
exit 1
EOF

cat >"$test_dir/bin/limine-mkinitcpio" <<'EOF'
#!/bin/bash
exit "${REBUILD_RESULT:-0}"
EOF

cat >"$test_dir/bin/gum" <<'EOF'
#!/bin/bash
exit 0
EOF

chmod +x "$test_dir/bin/"*

run_setup() {
  PATH="$test_dir/bin:$PATH" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_BLUETOOTH_UNLOCK_CONFIG_DIR="$test_dir/etc/omarchy" \
    OMARCHY_BLUETOOTH_UNLOCK_MKINITCPIO_DIR="$test_dir/etc/mkinitcpio.conf.d" \
    OMARCHY_BLUETOOTH_UNLOCK_MKINITCPIO_CONFIG="$test_dir/etc/mkinitcpio.conf" \
    OMARCHY_BLUETOOTH_UNLOCK_INITCPIO_DIR="$test_dir/usr/lib/initcpio" \
    OMARCHY_BLUETOOTH_UNLOCK_STATE_DIR="$test_dir/state" \
    "$ROOT/bin/omarchy-setup-security-bluetooth-unlock" "$@"
}

run_setup enable --device "$device" --controller "$controller" --yes --no-rebuild >/dev/null

config="$test_dir/etc/omarchy/bluetooth-unlock.conf"
dropin="$test_dir/etc/mkinitcpio.conf.d/zz-omarchy-bluetooth-unlock.conf"
install_hook="$test_dir/usr/lib/initcpio/install/omarchy-bluetooth-unlock"
runtime_hook="$test_dir/usr/lib/initcpio/hooks/omarchy-bluetooth-unlock"

[[ -f $config && -f $dropin && -x $install_hook && -x $runtime_hook ]] ||
  fail "Bluetooth unlock setup installs its complete boot configuration"
pass "Bluetooth unlock setup installs its complete boot configuration"

grep -Fxq "CONTROLLER=$controller" "$config" || fail "Bluetooth unlock records the selected controller"
grep -Fxq "DEVICE=$device" "$config" || fail "Bluetooth unlock records the selected keyboard"
[[ $(stat -c %a "$config") == "600" ]] || fail "Bluetooth unlock protects its device selection"
pass "Bluetooth unlock records only the selected bond with protected configuration"

resolved_hooks=$(bash -uc "HOOKS=(base udev keyboard resume encrypt filesystems); source '$dropin'; echo \"\${HOOKS[*]}\"")
[[ $resolved_hooks == "base udev keyboard resume omarchy-bluetooth-unlock encrypt filesystems" ]] ||
  fail "Bluetooth unlock is inserted immediately before encrypt" "$resolved_hooks"
pass "Bluetooth unlock is inserted immediately before encrypt"

resolved_hooks=$(bash -uc "HOOKS=(base udev keyboard omarchy-bluetooth-unlock block encrypt filesystems); source '$dropin'; echo \"\${HOOKS[*]}\"")
[[ $resolved_hooks == "base udev keyboard block omarchy-bluetooth-unlock encrypt filesystems" ]] ||
  fail "Bluetooth unlock is not duplicated on repeated setup" "$resolved_hooks"
pass "Bluetooth unlock is not duplicated on repeated setup"

! grep -Rq '/etc/shadow\|add_full_dir[[:space:]]\+/var/lib/bluetooth$' "$ROOT/default/initcpio" ||
  fail "Bluetooth unlock does not copy password hashes or every Bluetooth bond"
grep -Fq 'add_full_dir "$device_dir"' "$install_hook" ||
  fail "Bluetooth unlock copies only the selected device directory"
pass "Bluetooth unlock excludes password hashes and unrelated Bluetooth bonds"

run_setup status >/dev/null || fail "Bluetooth unlock reports enabled status"
pass "Bluetooth unlock reports enabled status"

run_setup disable --yes --no-rebuild >/dev/null
[[ ! -e $config && ! -e $dropin && ! -e $install_hook && ! -e $runtime_hook ]] ||
  fail "Bluetooth unlock disable removes every installed component"
pass "Bluetooth unlock disable removes every installed component"

# A failed build must not leave the next package update using broken settings.
if REBUILD_RESULT=1 run_setup enable --device "$device" --controller "$controller" --yes >/dev/null 2>&1; then
  fail "Bluetooth unlock propagates a failed image rebuild"
fi
[[ ! -e $config && ! -e $dropin && ! -e $install_hook && ! -e $runtime_hook ]] ||
  fail "Failed first enable restores the disabled configuration"
pass "Failed first enable restores the disabled configuration"

run_setup enable --device "$device" --controller "$controller" --yes --no-rebuild >/dev/null
printf '
# Preserve existing configuration
' >>"$config"
cp "$config" "$test_dir/expected-config"
if REBUILD_RESULT=1 run_setup disable --yes >/dev/null 2>&1; then
  fail "Bluetooth unlock propagates a failed disable rebuild"
fi
cmp -s "$config" "$test_dir/expected-config" && [[ $(stat -c %a "$config") == "600" && -f $dropin && -x $install_hook && -x $runtime_hook ]] ||
  fail "Failed disable restores the previous configuration and modes"
pass "Failed disable restores the previous configuration and modes"

if REBUILD_RESULT=1 run_setup enable --device "$device" --controller "$controller" --yes >/dev/null 2>&1; then
  fail "Bluetooth unlock propagates a failed re-enable rebuild"
fi
cmp -s "$config" "$test_dir/expected-config" || fail "Failed re-enable restores the previous device selection"
pass "Failed re-enable restores the previous device selection"

rm "$runtime_hook"
run_setup disable --yes --no-rebuild >/dev/null
[[ ! -e $config && ! -e $dropin && ! -e $install_hook ]] || fail "Disable removes a partial installation"
pass "Disable removes a partial installation"

printf 'HOOKS=(base systemd keyboard sd-encrypt filesystems)\n' >"$test_dir/etc/mkinitcpio.conf.d/zz_override.conf"
if run_setup enable --device "$device" --controller "$controller" --yes --no-rebuild >/dev/null 2>&1; then
  fail "Setup rejects a later override that replaces encrypt"
fi
[[ ! -e $config ]] || fail "Unsupported hooks leave configuration unchanged"
pass "Setup checks effective hooks rather than a superseded assignment"
rm "$test_dir/etc/mkinitcpio.conf.d/zz_override.conf"

if run_setup enable --device >/dev/null 2>&1; then
  fail "Setup rejects a missing device argument"
fi
pass "Setup rejects a missing device argument"

printf 'HOOKS=(base udev keyboard encrypt filesystems)\n' >"$test_dir/etc/mkinitcpio.conf.d/zz_override.conf"
if run_setup enable --device "$device" --controller "$controller" --yes --no-rebuild >/dev/null 2>&1; then
  fail "Setup rejects a later override that drops the Bluetooth hook"
fi
pass "Setup rejects a later override that drops the Bluetooth hook"
rm "$test_dir/etc/mkinitcpio.conf.d/zz_override.conf"

# Run the actual hook with filesystem paths redirected and process control
# stubbed. No host bus, adapter, daemon, or PID is touched.
sed -e "s|/run/|$test_dir/run/|g" \
  -e "s|/sys/class/bluetooth|$test_dir/sys/class/bluetooth|g" \
  -e "s|/usr/lib/bluetooth/bluetoothd|bluetoothd|g" \
  "$ROOT/default/initcpio/hooks/omarchy-bluetooth-unlock" >"$test_dir/runtime-hook"
cat >"$test_dir/bin/dbus-daemon" <<'EOF'
#!/bin/bash
[[ ${DBUS_FAIL:-0} == 0 ]] || exit 1
touch "$TEST_DIR/run/dbus/pid" "$TEST_DIR/run/dbus/system_bus_socket"
echo 424242
EOF
chmod +x "$test_dir/bin/dbus-daemon"
cat >"$test_dir/runtime-test" <<'EOF'
#!/bin/sh
set -eu
. "$TEST_DIR/runtime-hook"
bluetoothd() { echo "$*" >"$TEST_DIR/bluetooth-args"; }
kill() { echo "$*" >>"$TEST_DIR/kill-log"; return 1; }
sleep() { echo "$*" >>"$TEST_DIR/sleep-log"; }
run_hook
# Wait for the harmless background stub to finish before inspecting its log.
wait
run_cleanuphook
EOF
if [[ -x /usr/lib/initcpio/busybox ]]; then
  PATH="$test_dir/bin:$PATH" TEST_DIR="$test_dir" /usr/lib/initcpio/busybox ash "$test_dir/runtime-test"
  grep -Fxq -- '--nodetach' "$test_dir/bluetooth-args" || fail "Runtime keeps bluetoothd in the foreground for PID tracking"
  [[ $(wc -l <"$test_dir/sleep-log") == 30 ]] || fail "Runtime bounds adapter discovery to three seconds"
  [[ ! -e $test_dir/run/dbus/pid && ! -e $test_dir/run/dbus/system_bus_socket && ! -e $test_dir/run/bluetooth/omarchy-bluetoothd.pid ]] ||
    fail "Runtime removes its bus and daemon state before switch_root"
  pass "Runtime bounds adapter discovery and cleans up its own bus before switch_root"
  rm "$test_dir/bluetooth-args"
  DBUS_FAIL=1 PATH="$test_dir/bin:$PATH" TEST_DIR="$test_dir" /usr/lib/initcpio/busybox ash "$test_dir/runtime-test" 2>/dev/null
  [[ ! -e $test_dir/bluetooth-args ]] || fail "Runtime does not start BlueZ when D-Bus fails"
  pass "Runtime preserves the recovery path when D-Bus fails"
else
  echo "# SKIP: mkinitcpio BusyBox is unavailable; runtime lifecycle is unverified"
fi

sed -i 's/Class=0x002540/Class=0x002580/' "$test_dir/state/$controller/$device/info"
if run_setup enable --device "$device" --controller "$controller" --yes --no-rebuild >/dev/null 2>&1; then
  fail "Setup rejects a trusted mouse bond"
fi
pass "Setup rejects a trusted mouse bond"
sed -i 's/Class=0x002580/Appearance=0x03c1/' "$test_dir/state/$controller/$device/info"
run_setup enable --device "$device" --controller "$controller" --yes --no-rebuild >/dev/null
pass "Setup accepts a trusted BLE keyboard bond without a running target D-Bus"
