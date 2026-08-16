echo "Repair theme symlinks the state-move migration left dangling"

# 1781043107.sh re-linked legacy theme symlinks whose targets were stored as a
# literal "~/.config/omarchy/current/..." string. The replacement used the same
# literal tilde, which the filesystem never expands inside a symlink target, so
# btop, Helix, and VS Code/Cursor would have lost their theme while the
# migration reported success anyway. That migration is already marked applied
# everywhere it ran, so this one repairs any link it left dangling.
#
# No shipped Omarchy code ever wrote these six targets with a literal tilde, so
# this is expected to be a no-op almost everywhere, and it stays deliberately
# narrow to keep it that way. Only a target that starts with a literal "~/" is
# repaired: the filesystem never expands one, so such a link cannot ever have
# worked, while a custom link into a dotfiles repo is a real path even when that
# repo happens to be unmounted right now.

relink_if_dangling() {
  local link="$1"
  local expected_target="$2"
  local target

  [[ -L $link ]] || return 0

  target=$(readlink "$link") || return 0

  # Already pointing at the state directory.
  [[ $target == "$expected_target" ]] && return 0

  # Still resolves, so it is a working link we have no business rewriting.
  [[ -e $link ]] && return 0

  # Only an unexpandable literal-tilde target naming this theme file is ours.
  case "$target" in
    "~/"*/omarchy/current/theme/"${expected_target##*/}") ;;
    *) return 0 ;;
  esac

  ln -sfn "$expected_target" "$link"
}

current_state_dir="$HOME/.local/state/omarchy/current"

relink_if_dangling "$HOME/.config/btop/themes/current.theme" \
  "$current_state_dir/theme/btop.theme"
relink_if_dangling "$HOME/.config/helix/themes/omarchy.toml" \
  "$current_state_dir/theme/helix.toml"

for vscode_dir in "$HOME/.vscode" "$HOME/.vscode-insiders" "$HOME/.vscode-oss" "$HOME/.cursor"; do
  relink_if_dangling "$vscode_dir/extensions/omarchy-theme/themes/omarchy-color-theme.json" \
    "$current_state_dir/theme/vscode-theme.json"
done
