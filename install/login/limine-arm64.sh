if [ -z "$OMARCHY_ARM" ]; then
  echo "This script is for ARM64 systems only"
  exit 0
fi

# Skip if Limine is not supported (Asahi uses U-Boot, VMware uses GRUB)
if [ -n "$ASAHI_ALARM" ] || [ -n "$OMARCHY_SKIP_LIMINE" ]; then
  echo "Skipping Limine installation (bootloader not supported on this platform)"
  exit 0
fi

echo "Setting up Limine bootloader for ARM64..."

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

echo "Creating EFI boot entry..."
DISK=$(findmnt -n -o SOURCE /boot | sed 's/[0-9]*$//')
PART=$(findmnt -n -o SOURCE /boot | grep -o '[0-9]*$')

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
