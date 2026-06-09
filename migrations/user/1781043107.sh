echo "Move current Omarchy theme state to ~/.local/state"

legacy_current_dir="$HOME/.config/omarchy/current"
current_state_dir="$HOME/.local/state/omarchy/current"

mkdir -p "$HOME/.local/state/omarchy"

if [[ -e $legacy_current_dir || -L $legacy_current_dir ]]; then
  if [[ ! -e $current_state_dir && ! -L $current_state_dir ]]; then
    mv "$legacy_current_dir" "$current_state_dir"
  else
    if [[ -d $legacy_current_dir && -d $current_state_dir ]]; then
      cp -an "$legacy_current_dir/." "$current_state_dir/" 2>/dev/null || true
    fi
    rm -rf "$legacy_current_dir"
  fi
fi

replace_current_path() {
  local file="$1"

  [[ -f $file ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$HOME" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
home = sys.argv[2]
text = path.read_text()
replacements = {
  f"{home}/.config/omarchy/current": f"{home}/.local/state/omarchy/current",
  "~/.config/omarchy/current": "~/.local/state/omarchy/current",
  "../omarchy/current": "../../.local/state/omarchy/current",
}
for old, new in replacements.items():
  text = text.replace(old, new)
path.write_text(text)
PY
  else
    sed -i \
      -e 's|~/.config/omarchy/current|~/.local/state/omarchy/current|g' \
      -e 's|\.\./omarchy/current|../../.local/state/omarchy/current|g' \
      "$file"
  fi
}

for file in \
  "$HOME/.config/alacritty/alacritty.toml" \
  "$HOME/.config/foot/foot.ini" \
  "$HOME/.config/ghostty/config" \
  "$HOME/.config/hypr/hyprland.conf" \
  "$HOME/.config/hyprland-preview-share-picker/config.yaml" \
  "$HOME/.config/kitty/kitty.conf"; do
  replace_current_path "$file"
done

relink_current_symlink() {
  local link="$1"
  local target suffix

  [[ -L $link ]] || return 0
  target=$(readlink "$link") || return 0

  case "$target" in
    "$legacy_current_dir"/*)
      suffix=${target#"$legacy_current_dir"/}
      ln -sfn "$current_state_dir/$suffix" "$link"
      ;;
    "~/.config/omarchy/current/"*)
      suffix=${target#"~/.config/omarchy/current/"}
      ln -sfn "~/.local/state/omarchy/current/$suffix" "$link"
      ;;
  esac
}

for link in \
  "$HOME/.config/btop/themes/current.theme" \
  "$HOME/.config/helix/themes/omarchy.toml" \
  "$HOME/.vscode/extensions/omarchy-theme/themes/omarchy-color-theme.json" \
  "$HOME/.vscode-insiders/extensions/omarchy-theme/themes/omarchy-color-theme.json" \
  "$HOME/.vscode-oss/extensions/omarchy-theme/themes/omarchy-color-theme.json" \
  "$HOME/.cursor/extensions/omarchy-theme/themes/omarchy-color-theme.json"; do
  relink_current_symlink "$link"
done
