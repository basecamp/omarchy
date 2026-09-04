echo "Register the omarchy:// link handler so plugins can be installed from a web page"

app_dir="$HOME/.local/share/applications"
mkdir -p "$app_dir"
cp "$OMARCHY_PATH/applications/omarchy-url-handler.desktop" "$app_dir/"
update-desktop-database "$app_dir"
