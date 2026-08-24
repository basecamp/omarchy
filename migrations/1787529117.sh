echo "Regenerate noisy mise wrappers so they stop writing to stdout"

for wrapper in "$HOME/.local/bin"/*; do
  [[ -f $wrapper && -x $wrapper ]] || continue

  # Only rewrite the pre--quiet form that still pollutes stdout (#7426).
  package=$(sed -n 's/^mise use -g "\(.*\)" || exit 1$/\1/p' "$wrapper")
  bin=$(sed -n 's/^exec mise x ".*" -- "\(.*\)" "\$@"$/\1/p' "$wrapper")

  if [[ -n $package && -n $bin ]]; then
    omarchy-mise-install "$package" "$(basename "$wrapper")" "$bin"
  fi
done
