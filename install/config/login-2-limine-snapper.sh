if command -v limine &>/dev/null && ! command -v limine-entry-tool &>/dev/null; then
  yay -S --noconfirm --needed limine-mkinitcpio-hook limine-snapper-sync
fi

if command -v limine &>/dev/null && [ ! -f /etc/default/limine ]; then
  sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF

  PARTUUID=$(blkid -t TYPE=crypto_LUKS -s PARTUUID -o value)

  sudo tee /etc/default/limine <<EOF >/dev/null
TARGET_OS_NAME="Omarchy"

KERNEL_CMDLINE[default]="cryptdevice=PARTUUID=${PARTUUID}:cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rw quiet splash"

ENABLE_UKI=yes

ENABLE_LIMINE_FALLBACK=yes

# Find and add other bootloaders
FIND_BOOTLOADERS=yes

BOOT_ORDER="*, *fallback, Snapshots"

MAX_SNAPSHOT_ENTRIES=5
EOF

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

  sudo sed -i 's/^TIMELINE_CREATE="yes"/TIMELINE_CREATE="no"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT="50"/NUMBER_LIMIT="5"/' /etc/snapper/configs/{root,home}
  sudo sed -i 's/^NUMBER_LIMIT_IMPORTANT="10"/NUMBER_LIMIT_IMPORTANT="5"/' /etc/snapper/configs/{root,home}

  sudo limine-update
  sudo limine-snapper-sync
  chrootable_systemctl_enable limine-snapper-sync.service
fi

# Add UKI entry to UEFI machines to skip bootloader showing on normal boot
if [ -n "${OMARCHY_CHROOT_INSTALL:-}" ] && efibootmgr &>/dev/null && ! efibootmgr | grep -q Omarchy; then
  sudo efibootmgr --create \
    --disk "$(findmnt -n -o SOURCE /boot | sed 's/[0-9]*$//')" \
    --part "$(findmnt -n -o SOURCE /boot | grep -o '[0-9]*$')" \
    --label "Omarchy" \
    --loader "\\EFI\\Linux\\$(cat /etc/machine-id)_linux.efi"
fi
