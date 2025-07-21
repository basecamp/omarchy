echo "Ensure first-run flow isn't run for existing installations"

if [[ ! -f ~/.local/state/omarchy/after-first-run.mode ]]; then
  mkdir -p ~/.local/state/omarchy
  touch ~/.local/state/omarchy/after-first-run.mode
fi
