echo "Repair theme symlinks the state-move migration left dangling"

# 1781043107.sh re-linked legacy theme symlinks whose targets were stored as a
# literal "~/.config/omarchy/current/..." string. The replacement used the same
# literal tilde, which the filesystem never expands inside a symlink target, so
# btop, Helix, and VS Code/Cursor lost their theme and the migration reported
# success anyway. That migration is already marked applied everywhere it ran, so
# this one repairs the links it broke. It matches the shared suffix instead of
# enumerating spellings, ignores targets outside omarchy/current (custom links),
# and leaves links already pointing at the state directory alone.

relink_if_legacy() {
  local link="$1"
  local expected_target="$2"

  [[ -L $link ]] || return 0

  target=$(readlink "$link") || return 0

  # Already pointing at the state directory.
  [[ $target == "$expected_target" ]] && return 0

  # Only links whose target lived under omarchy/current are ours to relink.
  case "$target" in
    */omarchy/current/*) ;;
    *) return 0 ;;
  esac

  ln -sfn "$expected_target" "$link"
}

current_state_dir="$HOME/.local/state/omarchy/current"

relink_if_legacy "$HOME/.config/btop/themes/current.theme" \
  "$current_state_dir/theme/btop.theme"
relink_if_legacy "$HOME/.config/helix/themes/omarchy.toml" \
  "$current_state_dir/theme/helix.toml"

for vscode_dir in "$HOME/.vscode" "$HOME/.vscode-insiders" "$HOME/.vscode-oss" "$HOME/.cursor"; do
  relink_if_legacy "$vscode_dir/extensions/omarchy-theme/themes/omarchy-color-theme.json" \
    "$current_state_dir/theme/vscode-theme.json"
done
