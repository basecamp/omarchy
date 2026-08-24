echo "Refresh the Docker launcher now that daemon access goes through a prompt"

# The docker group is no longer granted by default (it is root-equivalent), so
# the Docker app entry and the Super+Shift+D hotkey open lazydocker through a
# polkit prompt via omarchy-launch-docker-tui. Existing installs still have the
# old ~/.local/share/applications/Docker.desktop that runs lazydocker directly,
# which now fails with a Docker socket permission error. Refresh just that entry;
# users who opted into sudoless Docker are unaffected either way.
dest="$HOME/.local/share/applications/Docker.desktop"
[[ -f $dest ]] || exit 0
cp "$OMARCHY_PATH/applications/Docker.desktop" "$dest"
