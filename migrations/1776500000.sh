echo "Enable SSD TRIM for LUKS-encrypted drives"

# Only apply if the system uses LUKS encryption
if ! grep -q "cryptdevice=" /etc/default/limine 2>/dev/null; then
  exit 0
fi

# Skip if allow-discards is already configured
if grep -q "allow-discards" /etc/default/limine 2>/dev/null; then
  exit 0
fi

# Add :allow-discards to the cryptdevice= parameter in the boot config
# Format: cryptdevice=device:dmname -> cryptdevice=device:dmname:allow-discards
sudo sed -i 's/\(cryptdevice=[^ "]*\)/\1:allow-discards/' /etc/default/limine

# Extract the dmname from cryptdevice=device:dmname and enable allow-discards
# on the running LUKS device so TRIM works immediately
DMNAME=$(grep -oP 'cryptdevice=[^: "]+:\K[^: "]+' /etc/default/limine | head -1)
if [[ -n $DMNAME ]] && [[ -b /dev/mapper/$DMNAME ]]; then
  sudo cryptsetup --allow-discards --persistent refresh "$DMNAME"
fi

# Regenerate initramfs and boot entry
sudo limine-mkinitcpio
sudo limine-update

echo "SSD TRIM enabled for LUKS encryption"
