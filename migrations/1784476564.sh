echo "Keep non-Latin keyboard layouts out of the initramfs so the LUKS passphrase stays typeable"

# Bundling vconsole.conf in the initramfs makes Plymouth apply the user's
# layout at the LUKS prompt. For layouts that don't type Latin letters, that
# makes the (Latin) passphrase untypeable and locks the user out (#6229).
# Drop the bundling for those layouts and rebuild the UKI. The packaged
# omarchy_hooks.conf now applies the same condition on every rebuild.

hooks_conf="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

layout=$(. /etc/vconsole.conf 2>/dev/null && echo "${XKBLAYOUT%%,*}")

if [[ $layout =~ ^(af|am|ara|bd|bg|by|et|ge|gr|il|in|iq|ir|kg|kh|kz|la|lk|mk|mm|mn|mv|np|rs|ru|sy|th|tj|ua)$ ]] &&
  [[ -f $hooks_conf ]] && grep -qx 'FILES+=(/etc/vconsole.conf)' "$hooks_conf"; then
  sudo sed -i '\|^FILES+=(/etc/vconsole.conf)$|d' "$hooks_conf"

  if omarchy-cmd-present limine-mkinitcpio; then
    sudo limine-mkinitcpio
  fi
fi
