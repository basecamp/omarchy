echo "Install oh-my-pi (omp) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install github:can1357/oh-my-pi omp
fi
