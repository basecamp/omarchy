echo "Regenerate mise wrappers to resolve their binaries before execution"

# `mise x "$package" -- "$bin"` still resolves the bare bin through PATH.
# When ~/.local/bin is ahead of mise's shims, that lookup finds the generated
# wrapper itself and execs it forever. Regenerate wrappers on the current
# template so they pass mise x the package-scoped absolute path instead.

current_template() {
  local package=$1 bin=$2

  printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$package" "$package" "$bin"
}

bin_dir="$HOME/.local/bin"

[[ -d $bin_dir ]] || exit 0

for wrapper in "$bin_dir"/*; do
  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || continue
  (($(stat -c%s "$wrapper") <= 1024)) || continue

  contents=$(<"$wrapper")
  package=$(sed -n 's/^mise use -g --quiet "\(.*\)" || exit 1$/\1/p' <<<"$contents")
  bin=$(sed -n 's/^exec mise x ".*" -- "\(.*\)" "\$@"$/\1/p' <<<"$contents")

  [[ -n $package && -n $bin ]] || continue
  [[ $contents == "$(current_template "$package" "$bin")" ]] || continue

  omarchy-mise-install "$package" "${wrapper##*/}" "$bin"
done
