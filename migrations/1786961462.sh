echo "Add Open in Terminal to the Files context menu"

# New installs get the extension seeded from /etc/skel; existing homes only
# pick it up by copying it over. Files loads extensions at startup, so the
# entry appears the next time it is launched.
extensions_dir="$HOME/.local/share/nautilus-python/extensions"

mkdir -p "$extensions_dir"
cp "$OMARCHY_PATH/default/nautilus-python/extensions/terminal.py" "$extensions_dir/"
