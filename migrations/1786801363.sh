echo "Drop the redundant Codex and Pi skill symlinks"

# Codex and Pi both discover ~/.agents/skills, so the per-harness copies never
# added anything. Only reclaim links pointing at Omarchy's own skills; anything
# else in those directories belongs to the user or the harness.
skills_source="$OMARCHY_PATH/default/agents/skills"

for skills_dir in ~/.codex/skills ~/.pi/agent/skills; do
  [[ -d $skills_dir ]] || continue

  for link in "$skills_dir"/*; do
    [[ -L $link ]] || continue

    target=$(readlink -f "$link") || continue
    [[ $target == "$(readlink -f "$skills_source")"/* ]] && rm "$link"
  done
done

# Pi's directory only ever held these links, so clear it out when it is empty.
# Codex keeps its own .system directory there, so leave that one alone.
rmdir ~/.pi/agent/skills 2>/dev/null || true
