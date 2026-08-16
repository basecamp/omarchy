echo "Point OpenCode at the npm package"

opencode_package="npm:@opencode-ai/cli"

if [[ -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  if [[ -f $HOME/.local/bin/opencode ]] && grep -Eq 'mise use -g (--quiet )?"opencode"' "$HOME/.local/bin/opencode"; then
    rm -f "$HOME/.local/bin/opencode"
  fi
  exit 0
fi

omarchy-mise-install "$opencode_package" opencode

if [[ -f $HOME/.config/mise/config.toml ]] && grep -q '@opencode-ai/cli' "$HOME/.config/mise/config.toml" && omarchy-cmd-present mise; then
  mise unuse -g opencode &>/dev/null || true
fi
