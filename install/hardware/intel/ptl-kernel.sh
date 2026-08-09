# Install the Panther Lake kernel on machines whose hardware needs its backports.
#
# linux-ptl carries fixes not yet in mainline, per machine:
#
#   Dell XPS            SDCA audio, PSR2 and Panel Replay display patches
#   HP EliteBook X G2i  the Panther Lake ACPI match-table entry for its RT712 +
#                       quad TAS2783 pairing, a component name for the TAS2783A
#                       so ALSA can resolve a speaker configuration, and the
#                       second link frequency its OV05C10 camera needs
#
# Both machines have no working speakers at all on a stock kernel, so this is
# not an optimisation.

if omarchy-hw-intel-ptl && { omarchy-hw-match "XPS" || omarchy-hw-match "EliteBook X G2i"; }; then
  echo "Detected Panther Lake hardware needing the PTL kernel, installing..."

  omarchy-pkg-add linux-ptl linux-ptl-headers
  pacman -Rdd --noconfirm linux linux-headers || true

  # linux-ptl doesn't provide=linux, so anything depending on linux drags the
  # stock kernel back in and the boot menu grows a second, slower entry.
  if pacman -Qq linux &>/dev/null; then
    echo "WARNING: stock linux kernel still installed alongside linux-ptl:"
    pacman -Qi linux | grep -i "required by"
  fi

  mkdir -p /etc/limine-entry-tool.d
  # Named to sort after omarchy-defaults.conf: drop-ins are read in order and
  # the last BOOT_ORDER wins, so an earlier-sorting name is a silent no-op.
  rm -f /etc/limine-entry-tool.d/dell-xps-panther-lake.conf
  rm -f /etc/limine-entry-tool.d/zz-dell-xps-panther-lake.conf
  cat > /etc/limine-entry-tool.d/zz-panther-lake.conf <<'EOF'
# Only show the Panther Lake kernel in the boot menu on machines that need it
BOOT_ORDER="linux-ptl*, *fallback, Snapshots"
EOF
fi
