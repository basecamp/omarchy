echo "Disable inherited text shadows in Waybar"

waybar_style="$HOME/.config/waybar/style.css"

if [[ -f $waybar_style ]] && ! grep -q "text-shadow: none" "$waybar_style"; then
  sed -i '/font-size: 12px;/a\  text-shadow: none;' "$waybar_style"
  sed -i '/tooltip {/,/^}/ s/padding: 2px;/padding: 2px;\n  text-shadow: none;/' "$waybar_style"

  cat >> "$waybar_style" << 'EOF'

tooltip * {
  text-shadow: none;
}
EOF

  omarchy-restart-waybar
fi
