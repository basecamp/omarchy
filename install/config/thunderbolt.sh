#!/bin/bash

# Auto-authorize Thunderbolt devices on hotplug (runtime)
sudo tee /etc/udev/rules.d/99-thunderbolt.rules > /dev/null <<'EOF'
ACTION=="add", SUBSYSTEM=="thunderbolt", ATTR{authorized}=="0", \
  RUN+="/bin/sh -c 'echo 1 > /sys$devpath/authorized'"
EOF

# Setup early boot Thunderbolt authorization for LUKS password entry
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

# Create initcpio install script
sudo tee "$INSTALL_DIR/thunderbolt_autoauth" > /dev/null <<'EOF'
#!/bin/sh
build() { add_runscript; }
help() {
    cat <<'HELPEOF'
Conservative TB auth (delay, skip 0-0, auth once) to keep DP link stable for splash/LUKS.
HELPEOF
}
EOF
sudo chmod +x "$INSTALL_DIR/thunderbolt_autoauth"

# Create runtime hook script
sudo tee "$HOOKS_DIR/thunderbolt_autoauth" > /dev/null <<'EOF'
#!/bin/sh
# Conservative Thunderbolt authorization to avoid killing DP link at KMS time.

run_hook() {
    # Give amdgpu+kms a moment to light the panel before we touch TB
    sleep 2

    for dev in /sys/bus/thunderbolt/devices/*; do
        base="$(basename "$dev")"
        # Skip domain/root (0-0) – writing there errors and can flap the bus
        [ "$base" = "0-0" ] && continue

        auth="$dev/authorized"
        [ -f "$auth" ] || continue

        cur="$(cat "$auth" 2>/dev/null || echo "?")"
        if [ "$cur" = "0" ]; then
            echo 1 > "$auth" 2>/dev/null
        fi
    done
}
EOF
sudo chmod +x "$HOOKS_DIR/thunderbolt_autoauth"

# TODO: Consider optimizing to run mkinitcpio -P once at end of install.sh instead of multiple times
# Currently runs in: nvidia.sh, login.sh, and here (thunderbolt.sh)
sudo mkinitcpio -P