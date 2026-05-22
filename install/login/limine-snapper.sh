if command -v limine &>/dev/null; then
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF
  sudo tee /etc/mkinitcpio.conf.d/thunderbolt_module.conf <<EOF >/dev/null
MODULES+=(thunderbolt)
EOF

  # Detect boot mode
  [[ -d /sys/firmware/efi ]] && EFI=true

  # If /etc/default/limine is already populated with a real cmdline (the ISO
  # orchestrator pre-writes it from the live install config), skip the
  # find+harvest+template-copy dance — we already have what we need. The
  # harvest path stays as a fallback for online reinstalls and any flow where
  # /etc/default/limine wasn't pre-populated.
  if [[ -f /etc/default/limine ]] && ! grep -q "@@CMDLINE@@" /etc/default/limine; then
    CMDLINE=$(grep '^KERNEL_CMDLINE\[default\]+=' /etc/default/limine | head -1 |
              sed 's|^KERNEL_CMDLINE\[default\]+="||; s|"$||')
  else
    # Find config location written by archinstall (legacy harvest path)
    if [[ -f /boot/EFI/arch-limine/limine.conf ]]; then
      limine_config="/boot/EFI/arch-limine/limine.conf"
    elif [[ -f /boot/EFI/BOOT/limine.conf ]]; then
      limine_config="/boot/EFI/BOOT/limine.conf"
    elif [[ -f /boot/EFI/limine/limine.conf ]]; then
      limine_config="/boot/EFI/limine/limine.conf"
    elif [[ -f /boot/limine/limine.conf ]]; then
      limine_config="/boot/limine/limine.conf"
    elif [[ -f /boot/limine.conf ]]; then
      limine_config="/boot/limine.conf"
    else
      echo "Error: Limine config not found" >&2
      exit 1
    fi

    CMDLINE=$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')

    if [[ -z ${CMDLINE// } ]]; then
      echo "Error: failed to extract kernel cmdline from $limine_config" >&2
      exit 1
    fi
    if [[ $CMDLINE != *root=* ]]; then
      echo "Error: extracted kernel cmdline has no root=: $CMDLINE" >&2
      exit 1
    fi

    sudo cp $OMARCHY_PATH/default/limine/default.conf /etc/default/limine
    sudo sed -i "s|@@CMDLINE@@|$CMDLINE|g" /etc/default/limine
  fi

  # Append any drop-in kernel cmdline configs (from hardware fix scripts, etc.)
  for dropin in /etc/limine-entry-tool.d/*.conf; do
    [ -f "$dropin" ] && cat "$dropin" | sudo tee -a /etc/default/limine >/dev/null
  done

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
  fi

  # Remove every alternate Limine config so limine-update can't pick a stale one
  # over our /boot/limine.conf.
  for stale in \
    /boot/EFI/arch-limine/limine.conf \
    /boot/EFI/BOOT/limine.conf \
    /boot/EFI/limine/limine.conf \
    /boot/limine/limine.conf; do
    [[ -f $stale ]] && sudo rm -f "$stale"
  done

  sudo cp $OMARCHY_PATH/default/limine/limine.conf /boot/limine.conf

  # limine-mkinitcpio-hook fired its post-transaction UKI build when archinstall
  # pacstrapped it (via omarchy-limine's depends) BEFORE /etc/default/limine and
  # /etc/kernel/cmdline existed, so the UKI on disk was built with an empty
  # cmdline. Delete every stale UKI for installed kernels so limine-update only
  # finds our about-to-be-rebuilt one.
  if [[ -d /boot/EFI/Linux ]]; then
    while IFS= read -r kname; do
      [[ -n $kname ]] || continue
      sudo rm -f "/boot/EFI/Linux/"*"_${kname}.efi" \
                 "/boot/EFI/Linux/"*"_${kname}-fallback.efi"
    done < <(cat /usr/lib/modules/*/pkgbase 2>/dev/null)
  fi

  # limine-update runs limine-install + limine-mkinitcpio (which reads
  # /etc/default/limine's KERNEL_CMDLINE[default] via limine-entry-tool and
  # embeds it into a freshly-built UKI). mkinitcpio -P alone does NOT trigger
  # limine's UKI pipeline — only this command does.
  sudo limine-update

  # Only snapshot root — /home is user data; rolling it back loses user work
  if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
    sudo snapper -c root create-config /
  fi
  sudo cp $OMARCHY_PATH/default/snapper/root /etc/snapper/configs/root

  # Disable btrfs quotas — full qgroup accounting is a major performance drag
  sudo btrfs quota disable / 2>/dev/null || true

  chrootable_systemctl_enable limine-snapper-sync.service
  LIMINE_CONFIGURED=true
fi

echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [[ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

# Final sanity check: assert the Limine config and UKI actually contain what
# they need to boot. Run AFTER snapper setup and hook re-enable so a
# validation failure doesn't leave the system half-configured.
if [[ ${LIMINE_CONFIGURED:-} == true ]]; then
  if ! grep -q "^/+Omarchy" /boot/limine.conf; then
    echo "Error: /boot/limine.conf does not contain an Omarchy entry" >&2
    exit 1
  fi
  if [[ ${CMDLINE:-} == *cryptdevice=* ]] && ! grep -q "cryptdevice=" /boot/limine.conf; then
    echo "Error: encrypted install but /boot/limine.conf has no cryptdevice=" >&2
    exit 1
  fi
fi

if [[ -n $EFI ]] && efibootmgr &>/dev/null; then
  # Remove the archinstall-created Limine entry
  while IFS= read -r bootnum; do
    sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
  done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
fi
