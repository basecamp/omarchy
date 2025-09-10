echo "Update imv.desktop file with the navigation fix"

src="$HOME/.local/share/omarchy/applications/imv.desktop"
dst="$HOME/.local/share/applications/imv.desktop"

exec_line=$(grep '^Exec' "$src")
if [ -n "$exec_line" ]; then
    sed -i "/^Exec/c\\$exec_line" "$dst"
fi