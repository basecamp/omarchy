echo "Regenerate mise wrappers to stop them recursing through PATH"

for wrapper in "$HOME/.local/bin"/*; do
  [[ -f $wrapper && -x $wrapper ]] || continue

  package=$(sed -n 's/^mise use -g "\(.*\)"$/\1/p' "$wrapper")
  bin=$(sed -n 's/^exec "\(.*\)" "\$@"$/\1/p' "$wrapper")

  if [[ -n $package && -n $bin ]]; then
    omarchy-mise-install "$package" "$(basename "$wrapper")" "$bin"
  fi
done
