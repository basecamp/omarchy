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
mkdir -p "$stub_bin" "$esp/$old_id" "$esp/$foreign_id"

cat >"$stub_bin/limine-entry-tool" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$CALLS"
sed -i "/machine-id=$2/d" "$OMARCHY_LIMINE_CONFIG"
SH
chmod +x "$stub_bin/limine-entry-tool"

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

factory_reset=$(<"$ROOT/bin/omarchy-system-factory-reset")
provision_owner=$(<"$ROOT/bin/omarchy-provision-owner")
[[ $factory_reset == *'previous-machine-id'* && $factory_reset == *'stage_provisioning_runtime'* &&
  $factory_reset == *'omarchy-limine-remove-machine-entry'* ]] ||
  fail "factory-reset staging does not carry its old identity into the fresh root"
[[ $provision_owner == *'previous-machine-id'* && $provision_owner == *'remove_previous_limine_entry'* ]] ||
  fail "first-boot provisioning does not retire the staged identity"
pass "the previous identity survives staging until first-boot cleanup completes"
