echo "Keep non-Latin keyboard layouts out of the initramfs so the LUKS passphrase stays typeable"

# Bundling vconsole.conf in the initramfs makes Plymouth apply the user's
# layout at the LUKS prompt. For layouts that don't type Latin letters, that
# makes the (Latin) passphrase untypeable and locks the user out (#6229).
# Drop the bundling for those layouts and rebuild the UKI. The packaged
# omarchy_hooks.conf now applies the same condition on every rebuild.

hooks_conf="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"

# vconsole.conf only guarantees KEYMAP, and it need not exist at all. Sourcing
# one that isn't there fails, and under omarchy-migrate's `bash -euo pipefail`
# that aborts every migration behind this one. Unset first so an exported
# XKBLAYOUT can't answer for a file that sets none.
layout=""
[[ -f /etc/vconsole.conf ]] && layout=$(unset XKBLAYOUT; . /etc/vconsole.conf; echo "${XKBLAYOUT:-}")
layout="${layout%%,*}"

if [[ $layout =~ ^(af|am|ara|bd|bg|by|et|ge|gr|il|in|iq|ir|kg|kh|kz|la|lk|mk|mm|mn|mv|np|rs|ru|sy|th|tj|ua)$ ]] &&
  [[ -f $hooks_conf ]] && grep -qx 'FILES+=(/etc/vconsole.conf)' "$hooks_conf"; then
  sudo sed -i '\|^FILES+=(/etc/vconsole.conf)$|d' "$hooks_conf"

  if omarchy-cmd-present limine-mkinitcpio; then
    sudo limine-mkinitcpio
  fi
fi
