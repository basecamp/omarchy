echo "Switching to polkit-gnome for better fingerprint authentication compatibility"
if ! command -v /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &>/dev/null; then
  yay -S --noconfirm --needed polkit-gnome
  systemctl --user stop hyprpolkitagent
  systemctl --user disable hyprpolkitagent
  yay -Rns --noconfirm hyprpolkitagent
  setsid /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 &
fi
