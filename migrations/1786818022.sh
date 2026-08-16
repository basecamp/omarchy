echo "Regenerate mise wrappers to serialize their config writes"

for wrapper in "$HOME/.local/bin"/*; do
  [[ -f $wrapper && -x $wrapper ]] || continue
  # -f follows a symlink, and regenerating through one replaces the alias.
  [[ -L $wrapper ]] && continue

  # Every shape the generator has emitted. flock is advisory, so one wrapper left
  # unrecognised loses the race again.
  use_package=$(sed -n 's/^mise use -g \(--quiet \)\{0,1\}"\(.*\)"\( || exit 1\)\{0,1\}$/\2/p' "$wrapper")
  [[ -n $use_package ]] || continue

  # Two exec lines would pair a package with the wrong binary.
  (( $(grep -c '^mise use -g ' "$wrapper") == 1 )) || continue
  (( $(grep -cE '^exec (mise (x|exec) )?"' "$wrapper") == 1 )) || continue

  exec_line=$(sed -n 's/^exec mise \(x\|exec\) "\([^"]*\)" -- "\([^"]*\)" "\$@"$/\2\t\3/p' "$wrapper")
  if [[ -n $exec_line ]]; then
    exec_package=${exec_line%%$'\t'*}
    bin=${exec_line##*$'\t'}
  else
    # Oldest shape names no package on the exec line. Extracted separately: a
    # package name carries slashes.
    bin=$(sed -n 's/^exec "\([^"]*\)" "\$@"$/\1/p' "$wrapper")
    exec_package=$use_package
  fi

  [[ -n $bin && $use_package == "$exec_package" ]] || continue

  # Regeneration replaces the file wholesale, so only touch one that is entirely
  # generated.
  if grep -qvE '^(#!/bin/bash|export MISE_MINIMUM_RELEASE_AGE=0|mise use -g .*|exec (mise (x|exec) )?".*|[[:space:]]*)$' "$wrapper"; then
    continue
  fi

  omarchy-mise-install "$use_package" "$(basename "$wrapper")" "$bin"
done
