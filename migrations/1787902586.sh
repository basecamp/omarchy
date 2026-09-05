echo "Remove legacy SDDM Hyprland config and stale pacsave files"

# SDDM loads all files in /etc/sddm.conf.d/ in alphabetical order. If a stale
# 10-wayland.conf.pacsave exists from a pacman upgrade, it sorts after
# 10-wayland.conf, overriding the Lua configuration and forcing the old
# hyprland.conf format which triggers Hyprland's deprecation banner.
if [[ -f /etc/sddm.conf.d/10-wayland.conf.pacsave || -f /usr/share/sddm/hyprland.conf ]]; then
  sudo rm -f /etc/sddm.conf.d/10-wayland.conf.pacsave /usr/share/sddm/hyprland.conf 2>/dev/null || true
fi
