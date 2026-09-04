echo "Refresh mise wrappers so they resolve @latest on each run"

# omarchy-mise-install now writes `mise use -g --quiet "<tool>@latest"` so a
# wrapper cannot stay pinned on a stale installed version. Wrappers already on
# disk still call the bare tool name (e.g. claude@latest is the target form).
# Rewrite the exact --quiet template through omarchy-mise-install.

stale_quiet_template() {
  printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g --quiet "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$1" "$1" "$2"
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
  [[ $package == *@latest ]] && continue
  [[ $contents == "$(stale_quiet_template "$package" "$bin")" ]] || continue

  omarchy-mise-install "$package" "${wrapper##*/}" "$bin"
done
