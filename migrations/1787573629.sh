echo "Regenerate mise wrappers that still print mise's own output to stdout"

# omarchy-mise-install gained `--quiet` on its `mise use -g` line so a wrapper
# stops printing mise's "tools: pkg@version" ahead of the tool's own output.
# That only changes wrappers written from then on, and the migration that
# installed the current ones is already marked complete, so every wrapper on
# disk keeps polluting stdout -- `claude --version` still answers with two
# lines, and a wrapper for a protocol-speaking command answers with a line its
# caller cannot parse. Rewrite them through omarchy-mise-install so the
# template stays in one place.

# Every generated form that predates --quiet, rebuilt from the package and bin
# the file itself names. Wrappers were written by all of these over time and
# only the ones a later migration happened to regenerate moved forward, so a
# machine can still be carrying any of them.
stale_template() {
  local form=$1 package=$2 bin=$3

  case $form in
  cooldown-export)
    printf '#!/bin/bash\nexport MISE_MINIMUM_RELEASE_AGE=0\nmise use -g "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$package" "$package" "$bin" ;;
  bail-on-failure)
    printf '#!/bin/bash\nmise use -g "%s" || exit 1\nexec mise x "%s" -- "%s" "$@"' "$package" "$package" "$bin" ;;
  mise-exec)
    printf '#!/bin/bash\nmise use -g "%s"\nexec mise exec "%s" -- "%s" "$@"' "$package" "$package" "$bin" ;;
  bare-exec)
    printf '#!/bin/bash\nmise use -g "%s"\nexec "%s" "$@"' "$package" "$bin" ;;
  esac
}

bin_dir="$HOME/.local/bin"

[[ -d $bin_dir ]] || exit 0

for wrapper in "$bin_dir"/*; do
  [[ -f $wrapper && ! -L $wrapper && -r $wrapper ]] || continue

  # A generated wrapper is four short lines. ~/.local/bin also holds real
  # binaries -- uv and uvx land here from the Python dev env -- so check the
  # size before reading rather than pulling a 30MB executable into memory to
  # discover it is not a wrapper.
  (($(stat -c%s "$wrapper") <= 1024)) || continue

  contents=$(<"$wrapper")

  package=$(sed -n 's/^mise use -g "\(.*\)"\( || exit 1\)*$/\1/p' <<<"$contents")
  bin=$(sed -n \
    -e 's/^exec mise x ".*" -- "\(.*\)" "\$@"$/\1/p' \
    -e 's/^exec mise exec ".*" -- "\(.*\)" "\$@"$/\1/p' \
    -e 's/^exec "\(.*\)" "\$@"$/\1/p' <<<"$contents")

  [[ -n $package && -n $bin ]] || continue

  # The whole file has to be one of those forms exactly. A wrapper someone has
  # added a line to is left as it is rather than silently regenerated without
  # that line, and one already carrying --quiet matches nothing here, which is
  # what makes re-running this a no-op.
  stale=0
  for form in cooldown-export bail-on-failure mise-exec bare-exec; do
    if [[ $contents == "$(stale_template "$form" "$package" "$bin")" ]]; then
      stale=1
      break
    fi
  done

  ((stale)) || continue

  omarchy-mise-install "$package" "${wrapper##*/}" "$bin"
done
