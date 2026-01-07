echo "Add icons for additional audio profiles in Waybar"

if ! grep -q '"headphone": ""' "$HOME/.config/waybar/config.jsonc"; then
  sed -i '
    /"pulseaudio": {/,/^[ ]*}/{
      /"format-icons": {/,/^[ ]*}/{
        /"default":/i\
\      "headphone": "",
      }
    }
  ' "$HOME/.config/waybar/config.jsonc"

  omarchy-restart-waybar
fi
