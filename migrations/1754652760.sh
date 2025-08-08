echo "Fix the expand icon margin in the Waybar style"

~/.local/share/omarchy/bin/omarchy-refresh-config waybar/style.css
~/.local/share/omarchy/bin/omarchy-restart-waybar || true
