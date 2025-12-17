#!/bin/bash

# Setup early boot Thunderbolt authorization for LUKS password entry
# Devices connected at boot are authorized for LUKS entry and will be
# automatically enrolled by bolt when it starts in userspace
INSTALL_DIR="/etc/initcpio/install"
HOOKS_DIR="/etc/initcpio/hooks"
CONF="/etc/mkinitcpio.conf"

sudo mkdir -p "$INSTALL_DIR" "$HOOKS_DIR"

# Add required modules to mkinitcpio.conf (insert after 'btrfs' if present)
# Only add amdgpu if AMD GPU is detected (not just AMD USB controllers, etc.)
if lspci | grep -Ei 'VGA|Display' | grep -qi 'AMD'; then
  NEEDED_MODS="amdgpu xhci_hcd xhci_pci thunderbolt typec ucsi_acpi typec_displayport usbhid hid_generic"
else
  NEEDED_MODS="xhci_hcd xhci_pci thunderbolt typec ucsi_acpi typec_displayport usbhid hid_generic"
fi

# Only modify if at least one needed module is not already present
NEED_PATCH=false
for m in $NEEDED_MODS; do
  if ! grep -qE "^[[:space:]]*MODULES=\([^)]*\b$m\b" "$CONF"; then
    NEED_PATCH=true
    break
  fi
done

if $NEED_PATCH; then
  # Insert all needed modules immediately after 'btrfs' in the MODULES line
  sudo sed -Ei \
    "s/^(MODULES=\([^)]*\bbtrfs\b)([^)]*\))$/\1 $(echo $NEEDED_MODS)\2/" \
    "$CONF"
fi

# Add thunderbolt_autoauth hook if not present (insert before 'encrypt')
if ! grep -q "thunderbolt_autoauth" "$CONF"; then
  sudo sed -Ei \
    "/^[[:space:]]*HOOKS=\(/ s/(block[[:space:]]+)(encrypt)/\1thunderbolt_autoauth \2/" \
    "$CONF"
fi

# Copy initcpio install script
sudo cp "$OMARCHY_PATH/default/thunderbolt/boot/thunderbolt_autoauth.install" "$INSTALL_DIR/thunderbolt_autoauth"
sudo chmod +x "$INSTALL_DIR/thunderbolt_autoauth"

# Copy runtime hook script
sudo cp "$OMARCHY_PATH/default/thunderbolt/boot/thunderbolt_autoauth.hook" "$HOOKS_DIR/thunderbolt_autoauth"
sudo chmod +x "$HOOKS_DIR/thunderbolt_autoauth"

# TODO: Consider optimizing to run mkinitcpio -P once at end of install.sh instead of multiple times
# Currently runs in: nvidia.sh, login.sh, and here (thunderbolt.sh)
echo "Y" | sudo mkinitcpio -P