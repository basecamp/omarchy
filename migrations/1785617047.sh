echo "Install oh-my-pi (omp) via mise wrapper"

if [[ ! -f $HOME/.local/state/omarchy/preinstalls-removed ]]; then
  omarchy-mise-install oh-my-pi omp
fi
