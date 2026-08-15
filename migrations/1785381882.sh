echo "Run walker's autostart service with the cairo GTK renderer"

# omarchy-launch-walker starts walker with GSK_RENDERER=cairo, but the resident
# service is normally already running from the XDG autostart entry, which had no
# environment override. That left walker rendering through GTK4's Vulkan backend,
# which can hard-freeze the session on amdgpu (#6443). Only the stock Exec line is
# rewritten, so any other keys the user set in the entry are preserved.
walker_autostart="$HOME/.config/autostart/walker.desktop"

if [[ -f $walker_autostart ]] && grep -q "^Exec=walker --gapplication-service$" "$walker_autostart"; then
  sed -i "s|^Exec=walker --gapplication-service$|Exec=env GSK_RENDERER=cairo walker --gapplication-service|" "$walker_autostart"

  # The autostart generator only re-reads the entry on reload, so apply it now
  # instead of waiting for the next login.
  systemctl --user daemon-reload
  systemctl --user try-restart app-walker@autostart.service
fi
