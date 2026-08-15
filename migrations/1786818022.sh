echo "Regenerate mise wrappers to serialize their config writes"

for wrapper in "$HOME/.local/bin"/*; do
  [[ -f $wrapper && -x $wrapper ]] || continue

  package=$(sed -n 's/^mise use -g \(--quiet \)\{0,1\}"\(.*\)" || exit 1$/\2/p' "$wrapper")
  bin=$(sed -n 's/^exec mise x "[^"]*" -- "\([^"]*\)" "\$@"$/\1/p' "$wrapper")

  if [[ -n $package && -n $bin ]]; then
    omarchy-mise-install "$package" "$(basename "$wrapper")" "$bin"
  fi
done
