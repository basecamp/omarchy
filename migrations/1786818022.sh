echo "Regenerate mise wrappers to serialize their config writes"

for wrapper in "$HOME/.local/bin"/*; do
  [[ -f $wrapper && -x $wrapper ]] || continue
  # -f follows a symlink, and regenerating through one would replace the alias
  # with a copy that stops tracking whatever it pointed at.
  [[ -L $wrapper ]] && continue

  # Every shape this generator has emitted, so that the installs carrying the
  # most wrappers are not the ones left behind: `mise use -g` with or without
  # --quiet and the `|| exit 1` guard, and an exec line that has been `mise x`,
  # the older `mise exec`, and older still a plain call to the binary with the
  # package named only on the line above. A wrapper left unrecognised keeps
  # writing the global config unlocked, and flock is advisory, so one of those is
  # enough to lose the race again.
  use_package=$(sed -n 's/^mise use -g \(--quiet \)\{0,1\}"\(.*\)"\( || exit 1\)\{0,1\}$/\2/p' "$wrapper")
  [[ -n $use_package ]] || continue

  # Exactly one of each. Two exec lines would take the package from one and the
  # command from the other, and write a wrapper that runs the wrong tool.
  (( $(grep -c '^mise use -g ' "$wrapper") == 1 )) || continue
  (( $(grep -cE '^exec (mise (x|exec) )?"' "$wrapper") == 1 )) || continue

  exec_line=$(sed -n 's/^exec mise \(x\|exec\) "\([^"]*\)" -- "\([^"]*\)" "\$@"$/\2\t\3/p' "$wrapper")
  if [[ -n $exec_line ]]; then
    exec_package=${exec_line%%$'\t'*}
    bin=${exec_line##*$'\t'}
  else
    # The oldest shape names no package on the exec line, so the one above it is
    # the only claim there is. Extracted separately rather than interpolated into
    # the expression above, because a package name carries slashes.
    bin=$(sed -n 's/^exec "\([^"]*\)" "\$@"$/\1/p' "$wrapper")
    exec_package=$use_package
  fi

  [[ -n $bin && $use_package == "$exec_package" ]] || continue

  # Regeneration replaces the file wholesale, so only touch one that is entirely
  # generated. A line this does not recognise means someone wrote their own
  # script around the same two lines, and rewriting it would throw the rest away
  # -- leaving one wrapper unlocked is the better of those two failures.
  if grep -qvE '^(#!/bin/bash|export MISE_MINIMUM_RELEASE_AGE=0|mise use -g .*|exec (mise (x|exec) )?".*|[[:space:]]*)$' "$wrapper"; then
    continue
  fi

  omarchy-mise-install "$use_package" "$(basename "$wrapper")" "$bin"
done
