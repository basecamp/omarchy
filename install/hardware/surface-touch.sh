# Touchscreen support for Surface devices with IPTS digitizers.
# The stock kernel has no driver for Intel's Precise Touch & Stylus (IPTS)
# subsystem, so on Surface Pro 4 and newer (plus Laptop Studio and Go 3+)
# the touchscreen never appears as an input device. Install the linux-surface
# kernel alongside the stock one from the project's signed repository;
# iptsd then decodes touch input and starts on demand via udev rules.
#
# Scoped to all Surface devices for now: on models whose touch already works
# with the stock kernel the extra kernel is unused but harmless, since the
# stock kernel stays installed and selectable.
if omarchy-hw-surface; then
  echo "Detected Surface device, installing linux-surface kernel for touchscreen support..."

  # The surface kernel is not signed with Microsoft keys, so skip when Secure
  # Boot would refuse to boot it.
  secure_boot="$(od -An -t1 /sys/firmware/efi/efivars/SecureBoot-* 2>/dev/null | tr -dc '0-9')"
  if [[ $secure_boot == "1" ]]; then
    echo "Secure Boot is enabled: skipping linux-surface install (touch will not work)."
  else
    # Trust the linux-surface package signing key before the repo lands,
    # so the first install against it can verify signatures.
    if ! pacman-key --list-keys 56C464BAAC421453 &>/dev/null; then
      curl -fsSL https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | pacman-key --add -
    fi
    pacman-key --lsign-key 56C464BAAC421453

    if ! grep -q '^\[linux-surface\]' /etc/pacman.conf; then
      cat >> /etc/pacman.conf <<'EOF'

[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
EOF
      # Sync the freshly added repo database before installing from it.
      pacman -Sy --noconfirm
    fi

    omarchy-pkg-add linux-surface linux-surface-headers iptsd

    # Boot the surface kernel by default so touch works out of the box; the
    # stock kernel remains installed and selectable. Named to sort after
    # omarchy-defaults.conf: drop-ins are read in order and the last
    # BOOT_ORDER wins, so an earlier-sorting name is a silent no-op.
    mkdir -p /etc/limine-entry-tool.d
    rm -f /etc/limine-entry-tool.d/surface-touch.conf
    cat > /etc/limine-entry-tool.d/zz-surface-touch.conf <<'EOF'
# Prefer the linux-surface kernel at boot on Surface devices
BOOT_ORDER="linux-surface*, linux*, *fallback, Snapshots"
EOF
  fi
fi
