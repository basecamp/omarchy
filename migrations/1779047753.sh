echo "Use omarchy-shell as the Quickshell IPC entry point"

for file in ~/.config/hypr/bindings.lua ~/.config/hypr/bindings/*.lua; do
  [[ -f $file ]] || continue
  sed -i 's/omarchy-shell-ipc-fast/omarchy-shell/g; s/omarchy-shell-ipc/omarchy-shell/g; s/omarchy-shell[[:space:]]\+--if-running/omarchy-shell/g' "$file"
done

omarchy-restart-shell
