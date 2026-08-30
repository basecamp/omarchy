echo "Add Messenger as a default web app"

mkdir -p "$HOME/.local/share/applications"

dest="$HOME/.local/share/applications/Messenger.desktop"
src="$OMARCHY_PATH/applications/Messenger.desktop"

# Leave an existing launcher alone — the user may already have added Messenger
# themselves, or customized the exec line.
if [[ -f $dest ]]; then
  exit 0
fi

if [[ -f $src ]]; then
  cp "$src" "$dest"
fi
