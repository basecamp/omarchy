echo "Remove temporary Wayland color manager disabling flag from existing Chromium configs"

# This reverts the workaround originally added by migration 1760401344.sh
# Remove flag and comment from chromium-flags.conf only if found
if [[ -f ~/.config/chromium-flags.conf ]]; then
    sed -i '/--disable-features=WaylandWpColorManagerV1/d' ~/.config/chromium-flags.conf
    sed -i '/# Chromium crash workaround for Wayland color management on Hyprland/d' ~/.config/chromium-flags.conf
fi

# Remove flag and comment from brave-flags.conf only if found
if [[ -f ~/.config/brave-flags.conf ]]; then
    sed -i '/--disable-features=WaylandWpColorManagerV1/d' ~/.config/brave-flags.conf
    sed -i '/# Chromium crash workaround for Wayland color management on Hyprland/d' ~/.config/brave-flags.conf
fi
