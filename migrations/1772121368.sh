echo "Install plymouth theme color support"

sudo cp "$OMARCHY_PATH/bin/omarchy-plymouth-update-theme" /usr/local/bin/omarchy-plymouth-update-theme
sudo chmod 755 /usr/local/bin/omarchy-plymouth-update-theme
sudo chown root:root /usr/local/bin/omarchy-plymouth-update-theme

echo "%wheel ALL=(root) NOPASSWD: /usr/local/bin/omarchy-plymouth-update-theme *" | sudo tee /etc/sudoers.d/omarchy-plymouth >/dev/null
sudo chmod 440 /etc/sudoers.d/omarchy-plymouth

# Apply current theme to limine and plymouth, preserving the user's wallpaper
current_bg=$(readlink "$HOME/.config/omarchy/current/background" 2>/dev/null)

omarchy-theme-refresh

if [[ -n $current_bg && -f $current_bg ]]; then
  ln -nsf "$current_bg" "$HOME/.config/omarchy/current/background"
  pkill -x swaybg
  setsid uwsm-app -- swaybg -i "$HOME/.config/omarchy/current/background" -m fill >/dev/null 2>&1 &
fi
