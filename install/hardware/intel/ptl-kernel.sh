# Install Panther Lake kernel for all Intel Panther Lake systems
# The linux-ptl kernel includes audio driver patches not yet in mainline.

if omarchy-hw-intel-ptl; then
  echo "Detected Intel Panther Lake, installing PTL kernel..."

  omarchy-pkg-add linux-ptl linux-ptl-headers
  pacman -Rdd --noconfirm linux linux-headers || true

  # linux-ptl doesn't provide=linux, so anything depending on linux drags the
  # stock kernel back in and the boot menu grows a second, slower entry.
  if pacman -Qq linux &>/dev/null; then
    echo "WARNING: stock linux kernel still installed alongside linux-ptl:"
    pacman -Qi linux | grep -i "required by"
  fi

  # For Dell XPS, also set boot order to only show PTL kernel
  if omarchy-hw-match "XPS"; then
    mkdir -p /etc/limine-entry-tool.d
    # Named to sort after omarchy-defaults.conf: drop-ins are read in order and
    # the last BOOT_ORDER wins, so an earlier-sorting name is a silent no-op.
    rm -f /etc/limine-entry-tool.d/dell-xps-panther-lake.conf
    cat > /etc/limine-entry-tool.d/zz-dell-xps-panther-lake.conf <<'EOF'
# Only show Panther Lake kernel in boot menu on Dell XPS Panther Lake
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
EOF
  fi
fi
