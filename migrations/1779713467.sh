echo "Disable inherited text shadows in Waybar"

waybar_style="$HOME/.config/waybar/style.css"
marker="omarchy:disable-text-shadow"

if [[ -f $waybar_style ]] && ! grep -qF "$marker" "$waybar_style"; then
  cat >>"$waybar_style" <<'EOF'

/* omarchy:disable-text-shadow */
* {
  text-shadow: none;
}

tooltip, tooltip * {
  text-shadow: none;
}
EOF

  omarchy-restart-waybar
fi
