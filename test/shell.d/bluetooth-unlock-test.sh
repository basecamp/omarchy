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
printf '[General]\nName=Test keyboard\n' >"$test_dir/state/$controller/$device/info"
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
