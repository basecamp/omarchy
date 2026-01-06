echo "Add opencode with dynamic themeing and Super + Shift + Ctrl + A binding"

omarchy-pkg-add opencode

# Add config using omarchy theme by default
if [[ ! -f ~/.config/opencode/opencode.json ]]; then
  mkdir -p ~/.config/opencode
  cp $OMARCHY_PATH/config/opencode/opencode.json ~/.config/opencode/opencode.json
fi

# Add binding if the key is available
BINDINGS_PATH="$HOME/.config/hypr/bindings.conf"
if ! grep -q "SUPER SHIFT CTRL, A" $BINDINGS_PATH; then
  sed -i '/SUPER SHIFT ALT, A/a bindd = SUPER SHIFT CTRL, A, opencode, exec, omarchy-launch-opencode' "$BINDINGS_PATH"
else
  echo "Add your own binding for opencode using omarchy-launch-opencode in $BINDINGS_PATH"
fi
