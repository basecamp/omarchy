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

replace_literal_in_file() {
  local file="$1"
  local old="$2"
  local new="$3"
  local tmp

  grep -Fq -- "$old" "$file" || return 0

  tmp=$(mktemp)
  OLD="$old" NEW="$new" awk '
    BEGIN {
      old = ENVIRON["OLD"]
      new = ENVIRON["NEW"]
    }
    {
      while ((pos = index($0, old)) > 0) {
        $0 = substr($0, 1, pos - 1) new substr($0, pos + length(old))
      }
      print
    }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

replace_current_path() {
  local file="$1"

  [[ -f $file ]] || return 0

  replace_literal_in_file "$file" "$HOME/.config/omarchy/current" "$HOME/.local/state/omarchy/current"
  replace_literal_in_file "$file" "~/.config/omarchy/current" "~/.local/state/omarchy/current"
  replace_literal_in_file "$file" "../omarchy/current" "../../.local/state/omarchy/current"
}

ensure_hyprland_state_path() {
  local file="$HOME/.config/hypr/hyprland.lua"
  local tmp

  [[ -f $file ]] || return 0
  grep -Fq '/.local/state/?.lua;' "$file" && return 0
  grep -Fq '/default/hypr/bootstrap.lua' "$file" && return 0
  grep -Fq '  .. "/.config/?.lua;"' "$file" || return 0

  tmp=$(mktemp)
  awk '
    !inserted && $0 == "  .. \"/.config/?.lua;\"" {
      print "  .. \"/.local/state/?.lua;\""
      print "  .. os.getenv(\"HOME\")"
      inserted = 1
    }
    { print }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

for file in \
  "$HOME/.config/alacritty/alacritty.toml" \
  "$HOME/.config/foot/foot.ini" \
  "$HOME/.config/ghostty/config" \
  "$HOME/.config/hypr/hyprland.conf" \
  "$HOME/.config/hypr/hyprland.lua" \
  "$HOME/.config/hyprland-preview-share-picker/config.yaml" \
  "$HOME/.config/kitty/kitty.conf"; do
  replace_current_path "$file"
done

ensure_hyprland_state_path

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
