echo "Allow updating of timezone by right-clicking on the clock (or running omarchy-cmd-tzupdate)"
if [[ ! -f /etc/sudoers.d/omarchy-tzupdate ]]; then
  bash ~/.local/share/omarchy/install/config/timezones.sh
  omarchy-refresh-waybar
fi
