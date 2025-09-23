echo "Adding thunderbolt module to mkinitcpio"

OMARCHY_HOOKS="/etc/mkinitcpio.conf.d/omarchy_hooks.conf"
RUN_MKINITCPIO=false

if ! grep -q '^MODULES=' $OMARCHY_HOOKS; then
  # Add a new MODULES line with thunderbolt
  sudo sed -i '1iMODULES=(thunderbolt)' $OMARCHY_HOOKS
  RUN_MKINITCPIO=true
elif grep -q '^MODULES=' $OMARCHY_HOOKS && ! grep -qE "^MODULES=.*(\bthunderbolt\b)" $OMARCHY_HOOKS; then
  # Add thunderbolt inside the existing MODULES=(...) list (before the closing paren)
  sudo sed -i -E "s/^(MODULES=\([^)]*)\)/\1 thunderbolt)/" $OMARCHY_HOOKS
  RUN_MKINITCPIO=true
fi

if [ "$RUN_MKINITCPIO" = true ]; then
  echo "Regenerating initramfs with thunderbolt module included"
  # From omarchy-refresh-plymouth
  if command -v limine-mkinitcpio &>/dev/null; then
    sudo limine-mkinitcpio
  else
    sudo mkinitcpio -P
  fi
fi