echo "Switch Brave Origin from the beta to the stable release"

if omarchy-pkg-present brave-origin-beta-bin; then
  default_browser=$(xdg-settings get default-web-browser 2>/dev/null || true)

  omarchy-pkg-aur-add brave-origin-bin
  omarchy-pkg-drop brave-origin-beta-bin

  mkdir -p ~/.config
  cp -f "$OMARCHY_PATH/config/chromium-flags.conf" ~/.config/brave-origin-flags.conf
  rm -f ~/.config/brave-origin-beta-flags.conf

  if [[ $default_browser == "brave-origin-beta.desktop" ]]; then
    omarchy-default-browser brave-origin
  fi
fi
