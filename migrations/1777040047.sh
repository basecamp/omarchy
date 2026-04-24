echo "Apply display and touchpad fixes for ASUS ExpertBook B9406 (Panther Lake)"

source "$OMARCHY_PATH/install/config/hardware/asus/fix-asus-ptl-b9406-display.sh"
source "$OMARCHY_PATH/install/config/hardware/asus/fix-asus-ptl-b9406-touchpad.sh"

if omarchy-hw-asus-expertbook-b9406; then
  DROP_IN="/etc/limine-entry-tool.d/asus-expertbook-b9406-display.conf"
  DEFAULT_LIMINE="/etc/default/limine"

  # Keep /etc/default/limine in sync with the drop-in. Install-time this is
  # handled by install/login/limine-snapper.sh; migrations have to do it
  # themselves. Idempotent: skip if the drop-in's header comment is already
  # present (a unique-to-this-drop-in marker, so it doesn't collide with
  # manual cmdline tweaks a user may have made).
  HEADER='# ASUS ExpertBook B9406 (Panther Lake / Xe3) display workarounds'
  if [[ -f $DROP_IN && -f $DEFAULT_LIMINE ]] && \
       ! grep -Fxq "$HEADER" "$DEFAULT_LIMINE"; then
    sudo tee -a "$DEFAULT_LIMINE" >/dev/null < "$DROP_IN"
  fi

  sudo limine-update
fi
