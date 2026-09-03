echo "Use Sunshine's systemd service as its only autostart"

autostart_file="$HOME/.config/hypr/autostart.lua"
autostart_entry='o.launch_on_start("sunshine")'
sunshine_service="app-dev.lizardbyte.app.Sunshine.service"

[[ -f $autostart_file ]] || exit 0
grep -Fxq "$autostart_entry" "$autostart_file" || exit 0

# Enabling without --now avoids starting a second server beside the instance
# Hyprland already launched in the current session. The service takes over at
# the next login after the legacy launch entry is removed.
if omarchy-pkg-present sunshine; then
  if ! systemctl --user enable "$sunshine_service"; then
    exit 1
  fi
fi

sed -i '\|^o\.launch_on_start("sunshine")$|d' "$autostart_file"
