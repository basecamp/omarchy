echo "Link the verify-plugin skill for the default coding agent"

# omarchy-provision-user links every shipped skill, but it only runs once, so
# existing installs need this one linked here.

skill="$OMARCHY_PATH/default/agents/skills/verify-plugin"

[[ -d $skill ]] || exit 0

for skills_dir in ~/.agents/skills ~/.claude/skills ~/.codex/skills ~/.pi/agent/skills; do
  mkdir -p "$skills_dir"
  link="$skills_dir/verify-plugin"

  if [[ -L $link ]]; then
    # Already Omarchy's link: leave it alone rather than rewrite it, so a
    # skills directory nobody can write to is not a migration that never
    # finishes. A link pointing anywhere else is a review method of someone's
    # own, and only a broken one is worth replacing.
    [[ $(readlink "$link") == "$skill" ]] && continue
    [[ -e $link ]] && continue
  elif [[ -e $link ]]; then
    # A real file or folder here is someone's own review method.
    continue
  fi

  # A skill that cannot be linked costs the review its default method, which is
  # not worth wedging every later migration over.
  ln -sfn "$skill" "$link" || echo "Could not link $link"
done
