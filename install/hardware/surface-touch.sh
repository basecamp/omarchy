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

pacman_conf=${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}
efivars_dir=${OMARCHY_EFIVARS_DIR:-/sys/firmware/efi/efivars}
entry_tool_dir=${OMARCHY_LIMINE_ENTRY_TOOL_DIR:-/etc/limine-entry-tool.d}

if omarchy-hw-surface; then
  echo "Detected Surface device, installing linux-surface kernel for touchscreen support..."

  # The efivarfs variable holds a 4-byte attributes header followed by the
  # actual 1-byte enabled flag, so read the byte at offset 4. The surface
  # kernel is not signed with Microsoft keys, so skip when Secure Boot would
  # refuse to boot it. Hardware leaves run without pipefail, so a failed or
  # short read would surface as an empty value: fail closed on anything that
  # is not a definite 0 or 1.
  secure_boot_var="$(compgen -G "$efivars_dir/SecureBoot-*" | head -1)"
  secure_boot=""
  if [[ -n $secure_boot_var ]]; then
    secure_boot="$(dd if=$secure_boot_var bs=1 skip=4 count=1 status=none | od -An -tu1 | tr -d '[:space:]')"
  fi

  if [[ $secure_boot == "1" ]]; then
    echo "Secure Boot is enabled: skipping linux-surface install (touch will not work)."
  elif [[ $secure_boot == "0" ]]; then
    # Trust the linux-surface package signing key before installing from the
    # repository, so package signatures verify on first use.
    if ! pacman-key --list-keys 56C464BAAC421453 &>/dev/null; then
      curl -fsSL https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc | pacman-key --add -
    fi
    pacman-key --lsign-key 56C464BAAC421453

    if ! grep -q '^\[linux-surface\]' "$pacman_conf"; then
      cat >> "$pacman_conf" <<'EOF'

[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
EOF
      # Full sync so the freshly added repository database exists and the
      # following install cannot run against mismatched mirrors as a partial
      # upgrade.
      pacman -Syu --noconfirm
    fi

    omarchy-pkg-add linux-surface linux-surface-headers iptsd

    # Keep the stock kernel as the default boot entry and leave the surface
    # kernel selectable for when touch support is wanted. Named to sort after
    # omarchy-defaults.conf: drop-ins are read in order and the last
    # BOOT_ORDER wins, so an earlier-sorting name is a silent no-op.
    mkdir -p "$entry_tool_dir"
    rm -f "$entry_tool_dir/surface-touch.conf"
    cat > "$entry_tool_dir/zz-surface-touch.conf" <<'EOF'
# Keep the stock kernel first on Surface devices; linux-surface stays
# available in the menu for touchscreen support.
BOOT_ORDER="linux, linux-surface*, *fallback, Snapshots"
EOF
  else
    echo "Could not determine the Secure Boot state: skipping linux-surface install (touch will not work)."
  fi
fi
