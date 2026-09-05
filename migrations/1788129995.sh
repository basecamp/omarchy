echo "Route Chromium browser notifications through the system notification center"

flag_files=(
  "$HOME/.config/chromium-flags.conf"
  "$HOME/.config/chrome-flags.conf"
  "$HOME/.config/microsoft-edge-stable-flags.conf"
  "$HOME/.config/brave-flags.conf"
  "$HOME/.config/brave-origin-flags.conf"
)

for flag_file in "${flag_files[@]}"; do
  [[ -f $flag_file ]] || continue
  grep -Eq '^--disable-features=([^,]*,)*SystemNotifications([,<]|$)' "$flag_file" && continue
  grep -Eq '^--enable-features=([^,]*,)*SystemNotifications([,<]|$)' "$flag_file" && continue

  if grep -q '^--enable-features=' "$flag_file"; then
    sed -i '0,/^--enable-features=/{/^--enable-features=/s/$/,SystemNotifications/;}' "$flag_file"
  else
    printf '%s\n' '--enable-features=SystemNotifications' >>"$flag_file"
  fi
done
