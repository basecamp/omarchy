echo "Add Chromium crash workaround flag for Hyprland to existing configs"

# Add flag to chromium-flags.conf if it exists and doesn't already have it
if [[ -f ~/.config/chromium-flags.conf ]]; then
  grep -q '\-\-disable-features=WaylandWpColorManagerV1' ~/.config/chromium-flags.conf || sed -i '$a # Chromium crash workaround for Wayland color management on Hyprland - see https://github.com/hyprwm/Hyprland/issues/11957\n--disable-features=WaylandWpColorManagerV1' ~/.config/chromium-flags.conf
fi

# Add flag to brave-flags.conf if it exists and doesn't already have it
if [[ -f ~/.config/brave-flags.conf ]]; then
  grep -q '\-\-disable-features=WaylandWpColorManagerV1' ~/.config/brave-flags.conf || sed -i '$a # Chromium crash workaround for Wayland color management on Hyprland - see https://github.com/hyprwm/Hyprland/issues/11957\n--disable-features=WaylandWpColorManagerV1' ~/.config/brave-flags.conf
fi
