if command -v limine &>/dev/null; then
  sudo pacman -S --noconfirm --needed limine-snapper-sync limine-mkinitcpio-hook

  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF

  [[ -f /boot/EFI/limine/limine.conf ]] || [[ -f /boot/EFI/BOOT/limine.conf ]] && EFI=true

  # Conf location is different between EFI and BIOS
  if [[ -n "$EFI" ]]; then
    # Check USB location first, then regular EFI location
    if [[ -f /boot/EFI/BOOT/limine.conf ]]; then
      limine_config="/boot/EFI/BOOT/limine.conf"
    else
      limine_config="/boot/EFI/limine/limine.conf"
    fi
  else
    limine_config="/boot/limine/limine.conf"
  fi

  # Double-check and exit if we don't have a config file for some reason
  if [[ ! -f $limine_config ]]; then
    echo "Error: Limine config not found at $limine_config" >&2
    exit 1
  fi

  CMDLINE=$(grep "^[[:space:]]*cmdline:" "$limine_config" | head -1 | sed 's/^[[:space:]]*cmdline:[[:space:]]*//')

  sudo tee /etc/default/limine <<EOF >/dev/null
TARGET_OS_NAME="Omarchy"

ESP_PATH="/boot"

KERNEL_CMDLINE[default]="$CMDLINE"
KERNEL_CMDLINE[default]+="quiet splash"

ENABLE_UKI=yes
CUSTOM_UKI_NAME="omarchy"

ENABLE_LIMINE_FALLBACK=yes

# Find and add other bootloaders
FIND_BOOTLOADERS=yes

BOOT_ORDER="*, *fallback, Snapshots"

MAX_SNAPSHOT_ENTRIES=5

SNAPSHOT_FORMAT_CHOICE=5
EOF

  # UKI and EFI fallback are EFI only
  if [[ -z $EFI ]]; then
    sudo sed -i '/^ENABLE_UKI=/d; /^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
  fi

  # We overwrite the whole thing knowing the limine-update will add the entries for us
  sudo tee /boot/limine.conf <<EOF >/dev/null
### Read more at config document: https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
#timeout: 3
default_entry: 2
interface_branding: Omarchy Bootloader
interface_branding_color: 2
hash_mismatch_panic: no

term_background: 1a1b26
backdrop: 1a1b26

# Terminal colors (Tokyo Night palette)
term_palette: 15161e;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;a9b1d6
term_palette_bright: 414868;f7768e;9ece6a;e0af68;7aa2f7;bb9af7;7dcfff;c0caf5

# Text colors
term_foreground: c0caf5
term_foreground_bright: c0caf5
term_background_bright: 24283b

EOF


  # Match Snapper configs if not installing from the ISO
  if [[ -z ${OMARCHY_CHROOT_INSTALL:-} ]]; then
    if ! sudo snapper list-configs 2>/dev/null | grep -q "root"; then
      sudo snapper -c root create-config /
    fi

    if ! sudo snapper list-configs 2>/dev/null | grep -q "home"; then
      sudo snapper -c home create-config /home
    fi
  fi

  # Tweak default Snapper configs
  sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/{root,home}

  chrootable_systemctl_enable limine-snapper-sync.service
fi

echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

sudo limine-update

if [[ -n $EFI ]] && efibootmgr &>/dev/null; then
    # Remove the archinstall-created Limine entry
  while IFS= read -r bootnum; do
    sudo efibootmgr -b "$bootnum" -B >/dev/null 2>&1
  done < <(efibootmgr | grep -E "^Boot[0-9]{4}\*? Arch Linux Limine" | sed 's/^Boot\([0-9]\{4\}\).*/\1/')
fi

# Move this to a utility to allow manual activation
# if [[ -n $EFI ]] && efibootmgr &>/dev/null &&
#   ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "American Megatrends" &&
#   ! cat /sys/class/dmi/id/bios_vendor 2>/dev/null | grep -qi "Apple"; then
#
#   uki_file=$(find /boot/EFI/Linux/ -name "omarchy*.efi" -printf "%f\n" 2>/dev/null | head -1)
#
#   if [[ -n "$uki_file" ]]; then
#     sudo efibootmgr --create \
#       --disk "$(findmnt -n -o SOURCE /boot | sed 's/p\?[0-9]*$//')" \
#       --part "$(findmnt -n -o SOURCE /boot | grep -o 'p\?[0-9]*$' | sed 's/^p//')" \
#       --label "Omarchy" \
#       --loader "\\EFI\\Linux\\$uki_file"
#   fi
# fi
