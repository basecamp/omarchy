echo "Modernize initramfs hooks to systemd-based for UKI compatibility"

HOOKS_CONF="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

# Only apply migration if the hooks config exists and contains old-style hooks
if [[ -f "$HOOKS_CONF" ]]; then
  if grep -q "base udev.*keymap consolefont.*encrypt" "$HOOKS_CONF"; then
    echo "Updating initramfs hooks from legacy udev-based to systemd-based..."

    # Replace legacy hooks with systemd equivalents:
    # - udev → systemd (systemd-based initramfs)
    # - keymap consolefont → sd-vconsole (systemd console with Plymouth integration)
    # - encrypt → sd-encrypt (systemd LUKS unlock with better FIDO2 support)
    sudo sed -i 's/base udev plymouth keyboard autodetect microcode modconf kms keymap consolefont block encrypt/base systemd plymouth keyboard autodetect microcode modconf kms sd-vconsole block sd-encrypt/' "$HOOKS_CONF"

    echo "Regenerating initramfs with new hooks..."
    sudo mkinitcpio -P

    echo "Initramfs hooks updated successfully."
    echo "Benefits: Better UKI integration, improved Plymouth support, enhanced FIDO2 compatibility"
  else
    echo "Hooks already modernized or config format unexpected. Skipping migration."
  fi
else
  echo "Omarchy hooks config not found. Skipping migration."
fi
