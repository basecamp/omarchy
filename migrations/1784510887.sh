echo "Switch Brave Origin from the beta to the stable release"

if omarchy-pkg-present brave-origin-beta-bin; then
  default_browser=$(xdg-settings get default-web-browser 2>/dev/null || true)

  if omarchy-pkg-aur-add brave-origin-bin; then
    :
  else
    aur_status=$?
    if (( aur_status == 2 )); then
      echo "Keeping Brave Origin Beta until its AUR replacement can be reviewed and installed."
      echo "Run omarchy-migrate interactively to retry this migration."
      exit 75
    fi
    exit "$aur_status"
  fi
  omarchy-pkg-drop brave-origin-beta-bin

  mkdir -p ~/.config
  cp -f "$OMARCHY_PATH/config/chromium-flags.conf" ~/.config/brave-origin-flags.conf
  rm -f ~/.config/brave-origin-beta-flags.conf

  if [[ $default_browser == "brave-origin-beta.desktop" ]]; then
    omarchy-default-browser brave-origin
  fi
fi
