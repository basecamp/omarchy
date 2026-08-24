echo "Regenerate noisy mise wrappers so they stop writing to stdout"

# Exact pre--quiet stub from omarchy-mise-install before #6940 (four lines).
# Matching the whole file avoids rewriting user scripts that merely call mise.
legacy_wrapper() {
  local package=$1 bin=$2
  printf '%s\n' \
    '#!/bin/bash' \
    'export MISE_MINIMUM_RELEASE_AGE=0' \
    "mise use -g \"$package\" || exit 1" \
    "exec mise x \"$package\" -- \"$bin\" \"\$@\""
}

for wrapper in "$HOME/.local/bin"/*; do
  [[ -f $wrapper && -x $wrapper ]] || continue

  package=$(sed -n '3s/^mise use -g "\(.*\)" || exit 1$/\1/p' "$wrapper")
  bin=$(sed -n '4s/^exec mise x ".*" -- "\(.*\)" "\$@"$/\1/p' "$wrapper")
  [[ -n $package && -n $bin ]] || continue

  # Package on the exec line must match the use line.
  exec_package=$(sed -n '4s/^exec mise x "\(.*\)" -- ".*" "\$@"$/\1/p' "$wrapper")
  [[ $exec_package == "$package" ]] || continue

  [[ $(<"$wrapper") == "$(legacy_wrapper "$package" "$bin")" ]] || continue

  omarchy-mise-install "$package" "$(basename "$wrapper")" "$bin"
done
