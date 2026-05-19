echo "Move omarchy-shell to the top-level shell directory"

if omarchy-cmd-present quickshell; then
  quickshell kill -p "$OMARCHY_PATH/default/quickshell"/omarchy-shell >/dev/null 2>&1 || true
fi

omarchy-restart-shell
