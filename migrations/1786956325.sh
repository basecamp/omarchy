echo "Install Grok through mise's first-party registry"

# mise now ships a first-party `grok` backend (http:grok). The earlier npm
# package name made `mise use -g grok` fail unless the user added a custom
# tool definition, and the x.ai curl installer then overwrote the wrapper.

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install grok
elif [[ -f $HOME/.local/bin/grok ]] && grep -Fq 'npm:@xai-official/grok' "$HOME/.local/bin/grok"; then
  rm -f "$HOME/.local/bin/grok"
fi

# The website installer also drops an `agent` symlink into ~/.local/bin.
# Use the raw target so a dangling link still matches after ~/.grok/bin is gone.
if [[ -L $HOME/.local/bin/agent ]]; then
  agent_target=$(readlink "$HOME/.local/bin/agent" || true)
  if [[ $agent_target == "$HOME/.grok/"* || $agent_target == *'/.grok/'* ]]; then
    rm -f "$HOME/.local/bin/agent"
  fi
fi
