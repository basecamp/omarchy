echo "Update Hyprland Lua entrypoint to load Omarchy bootstrap"

hyprland_config="$HOME/.config/hypr/hyprland.lua"

if [[ -f $hyprland_config ]] && ! grep -Fq '/default/hypr/bootstrap.lua' "$hyprland_config"; then
  tmp=$(mktemp)

  awk '
    BEGIN {
      replaced = 0
    }

    !replaced && $0 == "-- Load user modules from ~/.config and Omarchy defaults from $OMARCHY_PATH." {
      comment = $0
      got_next = getline next_line
      if (got_next > 0 && next_line == "package.path = os.getenv(\"HOME\")") {
        print "-- Omarchy'\''s bootstrap keeps path setup out of this user config."
        print "dofile((os.getenv(\"OMARCHY_PATH\") or \"/usr/share/omarchy\") .. \"/default/hypr/bootstrap.lua\")"
        replaced = 1

        while ((getline line) > 0) {
          if (line ~ /^[[:space:]]*\.\. package\.path$/) {
            break
          }
        }

        next
      }

      print comment
      if (got_next > 0) {
        print next_line
      }
      next
    }

    { print }
  ' "$hyprland_config" >"$tmp"

  mv "$tmp" "$hyprland_config"
fi
