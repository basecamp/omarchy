#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
esp="$test_tmp/boot"
config="$esp/limine.conf"
calls="$test_tmp/calls"
old_id=11111111111111111111111111111111
foreign_id=22222222222222222222222222222222
new_id=33333333333333333333333333333333
mkdir -p "$stub_bin" "$esp/$old_id" "$esp/$foreign_id"

cat >"$stub_bin/limine-entry-tool" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CALLS"
sed -i "/machine-id=$2/d" "$OMARCHY_LIMINE_CONFIG"
SH
chmod +x "$stub_bin/limine-entry-tool"

cat >"$stub_bin/limine-enroll-config" <<'SH'
#!/bin/bash
echo enroll >>"$CALLS"
SH
chmod +x "$stub_bin/limine-enroll-config"

cat >"$config" <<EOF
/Omarchy
  comment: machine-id=$old_id
  //Linux
    path: boot():/EFI/Linux/omarchy_linux.efi#oldhash
/Other Linux
  comment: machine-id=$foreign_id
  //Linux
    path: boot():/EFI/Linux/other_linux.efi#foreignhash
/Windows Boot Manager
  protocol: efi
  path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
EOF

CALLS="$calls" \
  OMARCHY_LIMINE_ESP_PATH="$esp" \
  OMARCHY_LIMINE_CONFIG="$config" \
  PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-limine-remove-machine-entry" "$old_id"

grep -Fxq -- "--remove-entry $old_id --no-hooks" "$calls" ||
  fail "factory reset does not target only its previous Limine identity"
[[ ! -e $esp/$old_id ]] || fail "factory reset keeps its retired machine-ID directory"
[[ -d $esp/$foreign_id ]] || fail "factory reset deletes another installation's boot directory"
grep -Fq "machine-id=$foreign_id" "$config" || fail "factory reset deletes another Linux boot entry"
grep -Fq '/Windows Boot Manager' "$config" || fail "factory reset deletes the Windows boot entry"
pass "factory reset retires only its own Limine identity"

: >"$calls"
if CALLS="$calls" OMARCHY_LIMINE_ESP_PATH="$esp" OMARCHY_LIMINE_CONFIG="$config" \
  PATH="$stub_bin:$PATH" bash "$ROOT/bin/omarchy-limine-remove-machine-entry" '../other' 2>/dev/null; then
  fail "an invalid machine ID reaches destructive cleanup"
fi
[[ -d $esp/$foreign_id ]] || fail "an invalid machine ID removes another installation"
[[ ! -s $calls ]] || fail "an invalid machine ID reaches limine-entry-tool"
pass "machine-ID cleanup rejects paths and malformed identities"

cat >"$config" <<EOF
default_entry: 2
/Windows
  protocol: efi
  path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
/+Other Linux
  comment: machine-id=$foreign_id
  //Linux
    path: boot():/EFI/Linux/other_linux.efi#foreignhash
/+Omarchy
  comment: machine-id=$new_id
  //Linux
    path: boot():/EFI/Linux/omarchy_linux.efi#newhash
EOF

: >"$calls"
CALLS="$calls" \
  OMARCHY_LIMINE_ESP_PATH="$esp" \
  OMARCHY_LIMINE_CONFIG="$config" \
  PATH="$stub_bin:$PATH" \
  bash "$ROOT/bin/omarchy-limine-default-machine-entry" "$new_id"

grep -Fxq 'default_entry: Omarchy/Linux' "$config" ||
  fail "factory reset leaves Limine targeting another OS after entry reordering"
grep -Fxq 'enroll' "$calls" || fail "the updated Limine config is not re-enrolled"
pass "factory reset keeps the rebuilt Omarchy entry as the boot target"

factory_reset=$(<"$ROOT/bin/omarchy-system-factory-reset")
provision_owner=$(<"$ROOT/bin/omarchy-provision-owner")
[[ $factory_reset == *'previous-machine-id'* &&
  $factory_reset == *'omarchy-limine-remove-machine-entry'* &&
  $factory_reset == *'omarchy-limine-default-machine-entry'* ]] ||
  fail "factory-reset staging does not carry its old identity into the fresh root"
[[ $provision_owner == *'previous-machine-id'* && $provision_owner == *'remove_previous_limine_entry'* ]] ||
  fail "first-boot provisioning does not retire the staged identity"
pass "the previous identity survives staging until first-boot cleanup completes"

[[ $factory_reset != *'stage_provisioning_runtime'* &&
  $factory_reset == *'install_provisioning_units "$next" "$unit_src"'* ]] ||
  fail "factory reset mixes a live provisioning worker with frozen snapshot helpers"
pass "factory reset keeps the snapshot provisioning runtime internally consistent"

[[ $factory_reset == *'awk -v marker="machine-id=$machine_id"'* ]] ||
  fail "factory reset verifies hashes belonging to every OS on the shared ESP"
pass "factory reset scopes boot-file verification to the rebuilt identity"
