echo "Rename the T2 Mac BCE module (apple-bce → t2bce) and repair the boot image"

# linux-t2 7.1.4 replaced the apple-bce driver with t2bce, so the apple-bce the
# installer put in the mkinitcpio MODULES list no longer resolves and every
# initramfs/UKI rebuild hard-fails — including the one the kernel upgrade to
# 7.1.4 just triggered, which left a stale UKI on the ESP.
#
# Both names are listed with mkinitcpio's optional '?' suffix because this
# migration only runs once: if this machine's linux-t2 hasn't reached 7.1.4 yet
# (lagging mirror, pinned kernel), apple-bce must keep working today and
# t2bce_vhci must take over on whichever future upgrade delivers the rename.
# t2bce_core/t2bce_dma come in via module dependencies.

conf="${OMARCHY_T2_MKINITCPIO_CONF:-/etc/mkinitcpio.conf.d/apple-t2.conf}"
modules_conf="${OMARCHY_T2_MODULES_CONF:-/etc/modules-load.d/t2.conf}"

if [[ -f $conf ]] && grep -q 'apple-bce ' "$conf"; then
  sudo sed -i 's/apple-bce /apple-bce? t2bce_vhci? /' "$conf"

  if [[ -f $modules_conf ]]; then
    sudo sed -i 's/^apple-bce$/t2bce_vhci/' "$modules_conf"
  fi

  # Rebuild what the failed hook skipped so the ESP matches the installed kernel.
  sudo limine-update
fi
