echo "Drop saved workspace layouts belonging to named workspaces"

# omarchy-hyprland-workspace-layout-toggle acted on whatever id activeworkspace
# reported, and a named workspace reports a negative one. Hyprland reads a
# leading "-" as a selector relative to the current workspace, so a layout saved
# for one is applied to workspace 1 at every login instead. The command no longer
# writes these; this clears the ones already on disk. It wrote to ~/.local/state
# whatever XDG_STATE_HOME said, so both are cleared.
removed=0

for state_home in "$HOME/.local/state" "${XDG_STATE_HOME:-}"; do
  [[ -n $state_home ]] || continue

  layouts_dir="$state_home/omarchy/workspace-layouts"
  [[ -d $layouts_dir ]] || continue

  for saved in "$layouts_dir"/-*.lua; do
    if [[ -f $saved ]]; then
      rm -f -- "$saved"
      removed=1
    fi
  done
done

# The package hook reloads Hyprland before migrations run, so the rule from the
# file just deleted is already applied to workspace 1. Hyprland watches the files
# it required and picks the deletion up on its own, but not for a user who has
# turned autoreload off, so ask for one.
if (( removed )); then
  hyprctl reload >/dev/null 2>&1 || true
fi
