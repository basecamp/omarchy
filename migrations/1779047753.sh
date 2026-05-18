echo "Run omarchy-shell as a supervised user service"

mkdir -p ~/.config/systemd/user
cp "$OMARCHY_PATH/config/systemd/user/omarchy-shell.service" ~/.config/systemd/user/omarchy-shell.service
systemctl --user daemon-reload

for file in ~/.config/hypr/bindings.lua ~/.config/hypr/bindings/*.lua; do
  [[ -f $file ]] || continue
  sed -i 's/omarchy-shell-ipc-fast/omarchy-shell/g; s/omarchy-shell-ipc/omarchy-shell/g; s/omarchy-shell[[:space:]]\+--if-running/omarchy-shell/g' "$file"
done

if ! systemctl --user is-active --quiet omarchy-shell.service && omarchy-cmd-present quickshell; then
  quickshell kill -p "$OMARCHY_PATH/shell" >/dev/null 2>&1 || true
  quickshell kill -p "$OMARCHY_PATH/default/quickshell"/omarchy-shell >/dev/null 2>&1 || true
fi

systemctl --user enable --now omarchy-shell.service || true
