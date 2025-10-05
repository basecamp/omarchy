if [ -z "$OMARCHY_ARM" ]; then
  echo "This script is for ARM64 systems only"
  return 0
fi

# Skip if Limine is not supported (Asahi uses U-Boot, VMware uses GRUB)
if [ -n "$ASAHI_ALARM" ] || [ -n "$OMARCHY_SKIP_LIMINE" ]; then
  echo "Skipping Limine installation (bootloader not supported on this platform)"
  return 0
fi

echo "Setting up Limine bootloader for ARM64..."

echo "Re-enabling mkinitcpio hooks..."

# Restore the specific mkinitcpio pacman hooks
if [ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled /usr/share/libalpm/hooks/90-mkinitcpio-install.hook
fi

if [ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled ]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook
fi

echo "mkinitcpio hooks re-enabled"

echo "Installing Limine, snapper, and mkinitcpio hook..."
yay -S --noconfirm --needed --answerdiff None --answerclean None --removemake snapper limine limine-mkinitcpio-hook

# Configure mkinitcpio hooks (no microcode for ARM)
echo "Configuring mkinitcpio hooks..."
sudo tee /etc/mkinitcpio.conf.d/omarchy_hooks.conf <<EOF >/dev/null
HOOKS=(base udev plymouth keyboard autodetect modconf kms keymap consolefont block encrypt filesystems fsck btrfs-overlayfs)
EOF

echo "Regenerating initramfs..."
sudo mkinitcpio -P

echo "Installing Limine EFI bootloader..."
EFI_DIR="/boot/EFI/BOOT"
sudo mkdir -p "$EFI_DIR"
sudo cp /usr/share/limine/BOOTAA64.EFI "$EFI_DIR/BOOTAA64.EFI"

echo "Creating initial Limine configuration..."
# Create config in EFI directory
sudo tee "$EFI_DIR/limine.conf" <<EOF >/dev/null
### Read more at config document: https://github.com/limine-bootloader/limine/blob/trunk/CONFIG.md
#timeout: 3
default_entry: 1
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

# Also create config at ESP root for NVMe boot device detection fallback
echo "Creating fallback Limine configuration at ESP root..."
sudo cp "$EFI_DIR/limine.conf" /boot/limine.conf

echo "Creating EFI boot entry..."
DISK=$(findmnt -n -o SOURCE /boot | sed 's/p\?[0-9]\+$//')
PART=$(findmnt -n -o SOURCE /boot | grep -o 'p\?[0-9]\+$' | sed 's/^p//')

# Check if Limine entry already exists
if ! efibootmgr | grep -q "Limine"; then
    sudo efibootmgr --create --disk "$DISK" --part "$PART" --label "Limine" --loader '\EFI\BOOT\BOOTAA64.EFI'
    echo "Created Limine boot entry"
else
    echo "Limine boot entry already exists"
fi

echo "Setting Limine as default boot option..."
LIMINE_NUM=$(efibootmgr | grep "Limine" | cut -c5-8)
if [[ -n "$LIMINE_NUM" ]]; then
    CURRENT_ORDER=$(efibootmgr | grep "^BootOrder:" | cut -d: -f2 | sed 's/ //g')
    # Remove Limine from current order if it exists
    NEW_ORDER=$(echo "$CURRENT_ORDER" | sed "s/$LIMINE_NUM,//g" | sed "s/,$LIMINE_NUM//g" | sed "s/$LIMINE_NUM//g")
    # Put Limine first
    sudo efibootmgr --bootorder "$LIMINE_NUM${NEW_ORDER:+,$NEW_ORDER}"
    echo "Limine set as default boot option"
fi

echo "Generating Limine configuration..."
sudo "$OMARCHY_PATH/bin/omarchy-limine-update"

echo "ARM64 Limine setup complete!"
