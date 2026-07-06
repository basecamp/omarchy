echo "Bundle the console keymap into the initramfs so Plymouth uses the right keyboard layout at the LUKS prompt"

HOOKS_CONF="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

if [[ -f $HOOKS_CONF ]] && ! grep -q '^FILES=' "$HOOKS_CONF"; then
  echo "FILES=(/etc/vconsole.conf)" | sudo tee -a "$HOOKS_CONF" >/dev/null

  if omarchy-cmd-present limine-mkinitcpio; then
    sudo limine-mkinitcpio
  fi
fi
