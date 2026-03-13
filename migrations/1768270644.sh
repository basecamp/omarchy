echo "Add icon for headset audio profile in Waybar"

if ! grep -q '"headset": ""' "$HOME/.config/waybar/config.jsonc"; then
  sed -i '
    /"pulseaudio": {/,/^[ ]*}/{
      /"format-icons": {/,/^[ ]*}/{
        /"default":/i\
\      "headset": "",
      }
    }
  ' "$HOME/.config/waybar/config.jsonc"

  omarchy-restart-waybar
fi
