echo "Repair leftover omp mise wrappers that use a bare package name"

wrapper="$HOME/.local/bin/omp"

if [[ -f $wrapper ]] && grep -Eq 'mise use -g .*"(omp|oh-my-pi)"' "$wrapper"; then
  if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
    omarchy-mise-install github:can1357/oh-my-pi omp
  else
    rm -f "$wrapper"
  fi
fi
