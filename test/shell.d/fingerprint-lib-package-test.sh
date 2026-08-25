#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

write_usb_devices() {
  rm -rf "$tmp_dir/devices"
  mkdir -p "$tmp_dir/devices"

  local index=0
  local spec
  for spec in "$@"; do
    local vendor=${spec%%:*}
    local remainder=${spec#*:}
    local product_id=${remainder%%:*}
    local product=""
    if [[ $remainder == *:* ]]; then
      product=${remainder#*:}
    fi
    local dev="$tmp_dir/devices/1-$index"

    mkdir -p "$dev"
    printf '%s\n' "$vendor" >"$dev/idVendor"
    printf '%s\n' "$product_id" >"$dev/idProduct"
    [[ -n $product ]] && printf '%s\n' "$product" >"$dev/product"
    index=$((index + 1))
  done
}

lib_package() {
  OMARCHY_USB_DEVICES_PATH="$tmp_dir/devices" "$ROOT/bin/omarchy-hw-fingerprint-lib-package"
}

assert_selects() {
  local expected="$1"
  local description="$2"
  local actual

  actual=$(lib_package) || fail "$description"
  [[ $actual == "$expected" ]] || fail "$description" "expected: $expected\nactual:   $actual"
  pass "$description"
}

# The exact USB ID of the ELAN match-on-chip v2 reader selects the
# replacement provider, even though its product string is the same
# "ELAN:ARM-M4" other Elan sensors carry.
write_usb_devices '04f3:0c4c:ELAN:ARM-M4'
assert_selects "aur libfprint-elanmoc2-git" "the 04f3:0c4c reader selects the replacement provider"

# Neighbouring IDs are different hardware. Some work with stock libfprint and
# some need other drivers, so only the exact pair may pick the replacement.
write_usb_devices '04f3:0c4b:ELAN:ARM-M4'
assert_selects "repo libfprint" "another 04f3 ELAN sensor keeps stock libfprint"

write_usb_devices '04f3:0c4d:ELAN:ARM-M4'
assert_selects "repo libfprint" "a third 04f3 ELAN sensor keeps stock libfprint"

write_usb_devices '04f3:0c4'
assert_selects "repo libfprint" "an ID sharing only a prefix keeps stock libfprint"

# A self-named reader with no special ID is ordinary supported hardware.
write_usb_devices '27c6:1234:Goodix Fingerprint USB Device'
assert_selects "repo libfprint" "an ordinary reader keeps stock libfprint"

write_usb_devices '04f3:0c3a:Fingerprint Device'
assert_selects "repo libfprint" "an unknown ELAN fingerprint product keeps stock libfprint"

mkdir -p "$tmp_dir/devices"
assert_selects "repo libfprint" "a machine with no matching USB devices keeps stock libfprint"

# Once the replacement provider is installed it wins over detection, so
# re-running setup never swaps a working alternate library back to stock.
mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/pacman" <<'EOF'
#!/bin/bash
[[ $1 == "-Q" && $2 == "libfprint-elanmoc2-git" ]] && exit 0
exit 1
EOF
chmod +x "$tmp_dir/bin/pacman"

installed_lib_package() {
  PATH="$tmp_dir/bin:$PATH" OMARCHY_USB_DEVICES_PATH="$tmp_dir/devices" \
    "$ROOT/bin/omarchy-hw-fingerprint-lib-package"
}

actual=$(installed_lib_package) || fail "an installed replacement provider is kept without a matching reader"
[[ $actual == "aur libfprint-elanmoc2-git" ]] ||
  fail "an installed replacement provider is kept without a matching reader" "expected: aur libfprint-elanmoc2-git\nactual:   $actual"
pass "an installed replacement provider is kept without a matching reader"

write_usb_devices '27c6:1234:Goodix Fingerprint USB Device'
actual=$(installed_lib_package) || fail "an installed replacement provider is kept alongside another reader"
[[ $actual == "aur libfprint-elanmoc2-git" ]] ||
  fail "an installed replacement provider is kept alongside another reader" "expected: aur libfprint-elanmoc2-git\nactual:   $actual"
pass "an installed replacement provider is kept alongside another reader"
