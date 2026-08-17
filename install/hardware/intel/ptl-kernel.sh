# Install the patched Panther Lake kernel on systems that still need it.
# Dell XPS models need the display patches. The ASUS ExpertBook B9406 needs
# the SoundWire quirk that ignores its firmware's phantom RT722 codec.

if { omarchy-hw-match "XPS" && omarchy-hw-intel-ptl; } || omarchy-hw-asus-expertbook-b9406; then
  echo "Detected hardware requiring the patched Panther Lake kernel..."

  omarchy-pkg-add linux-ptl linux-ptl-headers
  pacman -Rdd --noconfirm linux linux-headers || true

  # linux-ptl doesn't provide=linux, so anything depending on linux drags the
  # stock kernel back in and the boot menu grows a second, slower entry.
  if pacman -Qq linux &>/dev/null; then
    echo "WARNING: stock linux kernel still installed alongside linux-ptl:"
    pacman -Qi linux | grep -i "required by"
  fi

  boot_order_conf="${OMARCHY_PTL_BOOT_ORDER_CONF:-/etc/limine-entry-tool.d/zz-panther-lake-kernel.conf}"
  old_boot_order_conf="${OMARCHY_PTL_OLD_BOOT_ORDER_CONF:-/etc/limine-entry-tool.d/dell-xps-panther-lake.conf}"
  legacy_boot_order_conf="${OMARCHY_PTL_LEGACY_BOOT_ORDER_CONF:-/etc/limine-entry-tool.d/zz-dell-xps-panther-lake.conf}"
  mkdir -p "$(dirname "$boot_order_conf")"
  # Named to sort after omarchy-defaults.conf: drop-ins are read in order and
  # the last BOOT_ORDER wins, so an earlier-sorting name is a silent no-op.
  rm -f "$old_boot_order_conf" "$legacy_boot_order_conf"
  cat > "$boot_order_conf" <<'EOF'
# Prefer Omarchy's patched kernel on supported Panther Lake systems
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
EOF
fi
