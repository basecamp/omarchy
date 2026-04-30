echo "Enable FRED on Dell XPS Panther Lake systems"

DEFAULT_LIMINE="/etc/default/limine"

if omarchy-hw-match "XPS" && omarchy-hw-intel-ptl && [[ -f $DEFAULT_LIMINE ]] && ! grep -q 'fred=on' "$DEFAULT_LIMINE"; then
  source "$OMARCHY_PATH/install/config/hardware/intel/fred.sh"

  sudo limine-update
fi
