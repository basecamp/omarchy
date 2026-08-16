echo "Point OpenCode at the npm package and stop fighting v2 next pins"

opencode_package="npm:@opencode-ai/cli"
mise_config="$HOME/.config/mise/config.toml"
wrapper="$HOME/.local/bin/opencode"

if [[ -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  if [[ -f $wrapper ]] && grep -Eq 'mise use -g (--quiet )?"opencode"' "$wrapper"; then
    rm -f "$wrapper"
  fi
  exit 0
fi

omarchy-mise-install "$opencode_package" opencode

if [[ -f $mise_config ]] && grep -q '@opencode-ai/cli' "$mise_config" && omarchy-cmd-present mise; then
  mise unuse -g opencode &>/dev/null || true
fi
