# Fix suspend/resume on MacBookPro14,1 (2017 13" Intel, no Touch Bar).
#
# This machine hangs or fails to resume from the firmware's default S3 ("deep")
# sleep. Two changes make s2idle suspend reliable:
#   1. Default to s2idle instead of deep (S3 is broken on this platform).
#   2. Blacklist the thunderbolt module, which otherwise prevents a clean resume.
#
# Trade-off: blacklisting thunderbolt disables Thunderbolt device tunneling
# (TB3 docks, eGPUs). USB-C charging, USB, and DisplayPort alt-mode are
# unaffected, as those run through the xHCI / DP controllers, not the TB driver.
#
# Scope is limited to MacBookPro14,1 — the only model this was verified on. The
# sibling 14,2/14,3 share the platform and likely benefit, but were untested
# (and 14,3's discrete GPU may need more), so they are deliberately excluded.
MACBOOK_MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)

if [[ $MACBOOK_MODEL == "MacBookPro14,1" ]]; then
  echo "Detected MacBook model: $MACBOOK_MODEL"
  echo "Applying s2idle suspend fix..."

  # 1. Blacklist the thunderbolt driver (the resume blocker).
  cat <<EOF | sudo tee /etc/modprobe.d/omarchy-mbp-suspend-thunderbolt.conf >/dev/null
# Omarchy: blacklist thunderbolt to fix suspend/resume on MacBookPro14,1
blacklist thunderbolt
EOF

  # 2. Default to s2idle instead of the broken S3 ("deep") sleep state.
  DROP_IN="/etc/limine-entry-tool.d/apple-mbp-suspend-s2idle.conf"

  if [[ ! -f $DROP_IN ]] || ! grep -q 'mem_sleep_default=s2idle' "$DROP_IN"; then
    sudo mkdir -p /etc/limine-entry-tool.d
    cat <<EOF | sudo tee "$DROP_IN" >/dev/null
# Omarchy: default to s2idle suspend on MacBookPro14,1 (S3 is broken)
KERNEL_CMDLINE[default]+=" mem_sleep_default=s2idle"
EOF
  fi
fi
