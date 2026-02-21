echo "Protect /boot vfat mounts and restore mkinitcpio hooks"

MKINITCPIO_DROPIN="/etc/mkinitcpio.conf.d/zz-omarchy-vfat.conf"
HOOKS_DIR="/usr/share/libalpm/hooks"
changed=false

sudo mkdir -p /etc/mkinitcpio.conf.d || exit 1

if [[ ! -f $MKINITCPIO_DROPIN ]] || ! grep -Eq 'MODULES\+=\([^)]*\bvfat\b[^)]*\)' "$MKINITCPIO_DROPIN"; then
  sudo tee "$MKINITCPIO_DROPIN" <<EOF >/dev/null || exit 1
MODULES+=(vfat)
EOF
  changed=true
fi

restore_hook() {
  local disabled="$1"
  local enabled="${disabled%.disabled}"

  if [[ -f $disabled ]]; then
    changed=true

    if [[ -f $enabled ]]; then
      sudo rm -f "$disabled" || exit 1
    else
      sudo mv "$disabled" "$enabled" || exit 1
    fi
  fi
}

restore_hook "$HOOKS_DIR/90-mkinitcpio-install.hook.disabled"
restore_hook "$HOOKS_DIR/60-mkinitcpio-remove.hook.disabled"

if [[ $changed == "true" ]]; then
  if ! findmnt -n /boot >/dev/null; then
    echo "Mounting /boot before rebuilding boot artifacts"
    sudo mount /boot || exit 1
  fi

  if omarchy-cmd-present limine-mkinitcpio; then
    sudo limine-mkinitcpio || exit 1
  elif omarchy-cmd-present mkinitcpio; then
    sudo mkinitcpio -P || exit 1
  else
    echo "Error: no initramfs rebuild command found"
    exit 1
  fi

  if omarchy-cmd-present limine-update; then
    sudo limine-update || exit 1
  fi

  omarchy-state set reboot-required
fi
