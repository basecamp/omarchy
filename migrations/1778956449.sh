echo "Switch polkit authentication to omarchy-shell"

# The default Hyprland autostart now uses omarchy-shell's native Quickshell
# Polkit agent. Remove any stale user override that starts the old GTK agent.
if [[ -f ~/.config/hypr/autostart.lua ]]; then
  sed -i '/polkit-gnome-authentication-agent-1/d' ~/.config/hypr/autostart.lua
fi

pkill -u "$USER" -f '^/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1$' 2>/dev/null || true

omarchy-pkg-drop polkit-gnome

omarchy-restart-shell
