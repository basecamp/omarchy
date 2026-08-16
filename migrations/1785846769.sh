echo "Install default coding agent mise wrappers"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install github:can1357/oh-my-pi omp
  omarchy-mise-install npm:@xai-official/grok grok
  omarchy-mise-install crush
elif [[ -f $HOME/.local/bin/omp ]] && grep -Eq 'mise use -g .*"oh-my-pi"' "$HOME/.local/bin/omp"; then
  rm -f "$HOME/.local/bin/omp"
fi
