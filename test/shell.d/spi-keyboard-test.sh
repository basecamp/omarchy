#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

# The leaf reads /sys/class/dmi/id/product_name and writes under
# /etc/mkinitcpio.conf.d, so a sandboxed copy with those paths rewritten is
# used, like the other install/hardware tests.
leaf="$tmp_dir/leaf.sh"
sed -e "s|/sys/class/dmi/id/product_name|$tmp_dir/product_name|g" \
  -e "s|/etc/mkinitcpio.conf.d|$tmp_dir/mkinitcpio.conf.d|g" \
  "$ROOT/install/hardware/apple/fix-spi-keyboard.sh" >"$leaf"
chmod +x "$leaf"

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/omarchy-pkg-add" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PKG_ADD_LOG"
EOF
cat >"$tmp_dir/bin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
chmod +x "$tmp_dir/bin"/*

run_leaf() {
  printf '%s\n' "$1" >"$tmp_dir/product_name"
  : >"$tmp_dir/pkg-add.log"
  PKG_ADD_LOG="$tmp_dir/pkg-add.log" \
    PATH="$tmp_dir/bin:$PATH" \
    bash "$leaf"
}

# A matched MacBook: the initramfs drop-in has to keep the SPI modules (this
# is what makes the keyboard work at the LUKS prompt), but the DKMS package is
# obsolete — applespi is in-tree and the out-of-tree copy cannot build on
# modern kernels — so it must not be installed anymore.
run_leaf "MacBookPro14,1"
[[ -s $tmp_dir/pkg-add.log ]] &&
  fail "a matched MacBook no longer installs the obsolete DKMS package" \
    "$(cat "$tmp_dir/pkg-add.log")"
grep -q '^MODULES=(applespi intel_lpss_pci spi_pxa2xx_platform)$' \
  "$tmp_dir/mkinitcpio.conf.d/macbook_spi_modules.conf" ||
  fail "the SPI initramfs drop-in is still written" \
    "$(cat "$tmp_dir/mkinitcpio.conf.d/macbook_spi_modules.conf" 2>/dev/null || echo missing)"
pass "matched MacBook keeps the initramfs drop-in and skips the DKMS package"

# An unmatched machine must be left completely alone.
rm -rf "$tmp_dir/mkinitcpio.conf.d"
run_leaf "MacBookPro15,2"
[[ -s $tmp_dir/pkg-add.log ]] &&
  fail "an unmatched machine does not install the DKMS package"
[[ -e $tmp_dir/mkinitcpio.conf.d ]] &&
  fail "an unmatched machine does not write the drop-in"
pass "unmatched hardware is untouched"

# Nothing installs the package now, so the ISO has no reason to cache it.
! grep -qx 'macbook12-spi-driver-dkms' "$ROOT/install/omarchy-other.packages" ||
  fail "the ISO no longer caches macbook12-spi-driver-dkms"
pass "the obsolete DKMS package is gone from the ISO package cache list"

# The install script no longer adds the package, but machines that ran the
# old installer still carry one that fails to build on every kernel update
# once linux-headers is present. The migration drops it idempotently,
# following the tiny-dfr precedent.
cat >"$tmp_dir/bin/omarchy-pkg-present" <<'EOF'
#!/bin/bash
[[ -e $PKG_STATE ]] && [[ ${1:-} == macbook12-spi-driver-dkms ]]
EOF
cat >"$tmp_dir/bin/omarchy-pkg-drop" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PKG_DROP_LOG"
rm -f "$PKG_STATE"
EOF
chmod +x "$tmp_dir/bin/omarchy-pkg-present" "$tmp_dir/bin/omarchy-pkg-drop"

migration="$ROOT/migrations/1788476400.sh"
: >"$tmp_dir/pkg.installed"
: >"$tmp_dir/pkg-drop.log"
PKG_STATE="$tmp_dir/pkg.installed" PKG_DROP_LOG="$tmp_dir/pkg-drop.log" \
  PATH="$tmp_dir/bin:$PATH" HOME="$tmp_dir" bash "$migration"
grep -qx macbook12-spi-driver-dkms "$tmp_dir/pkg-drop.log" ||
  fail "the migration drops the obsolete DKMS package" \
    "$(cat "$tmp_dir/pkg-drop.log")"
drops_before=$(wc -l <"$tmp_dir/pkg-drop.log")
PKG_STATE="$tmp_dir/pkg.installed" PKG_DROP_LOG="$tmp_dir/pkg-drop.log" \
  PATH="$tmp_dir/bin:$PATH" HOME="$tmp_dir" bash "$migration"
(( $(wc -l <"$tmp_dir/pkg-drop.log") == drops_before )) ||
  fail "the migration only drops the package once" "$(cat "$tmp_dir/pkg-drop.log")"
pass "installed machines get the obsolete DKMS package removed once"

pass "SPI keyboard detection writes only the needed initramfs drop-in"
