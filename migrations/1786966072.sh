echo "Prefer footclient when Foot is the default terminal"

# Stock footclient.desktop drops X-TerminalArgAppId. Do not create a user
# xdg-terminals.list when none exists; quattro retired that file.

omarchy-cmd-present footclient || exit 0

list="$HOME/.config/xdg-terminals.list"
first=""
if [[ -f $list ]]; then
  first=$(grep -Ev '^\s*(#|$)' "$list" | head -n 1 || true)
fi

[[ -z $first || $first == "foot.desktop" || $first == "footclient.desktop" ]] || exit 0

mkdir -p "$HOME/.local/share/applications"
cp -f "$OMARCHY_PATH/applications/footclient.desktop" "$HOME/.local/share/applications/footclient.desktop"

if [[ $first == "foot.desktop" ]]; then
  cat >"$list" <<EOF
# Terminal emulator preference order for xdg-terminal-exec
# The first found and valid terminal will be used
footclient.desktop
EOF
fi

systemctl --user enable --now foot-server.socket || true
