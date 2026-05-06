echo "Add Foot terminal config and theme support"

if [[ ! -f ~/.config/foot/foot.ini ]]; then
  mkdir -p ~/.config/foot
  cp -Rpf "$OMARCHY_PATH/config/foot/foot.ini" ~/.config/foot/foot.ini
elif ! grep -q "^primary-paste=none" ~/.config/foot/foot.ini; then
  sed -i '/^clipboard-copy=Control+Insert/a primary-paste=none' ~/.config/foot/foot.ini
fi

if [[ -f ~/.config/omarchy/current/theme/foot.ini ]]; then
  sed -i 's/^\[colors\]$/[colors-dark]/' ~/.config/omarchy/current/theme/foot.ini
fi

if [[ ! -f ~/.config/omarchy/current/theme/foot.ini && -f ~/.config/omarchy/current/theme/colors.toml ]]; then
  sed_script=$(mktemp)

  while IFS='=' read -r key value; do
    key="${key//[\"\' ]/}"
    [[ $key && $key != \#* ]] || continue
    value="${value#*[\"\']}"
    value="${value%%[\"\']*}"

    printf 's|{{ %s }}|%s|g\n' "$key" "$value"
    printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}"
  done <~/.config/omarchy/current/theme/colors.toml >"$sed_script"

  sed -f "$sed_script" "$OMARCHY_PATH/default/themed/foot.ini.tpl" >~/.config/omarchy/current/theme/foot.ini
  rm "$sed_script"
fi

if omarchy-cmd-present foot; then
  mkdir -p ~/.local/share/applications
  rm -f ~/.local/share/applications/org.codeberg.dnkl.foot.desktop
  cp -Rpf "$OMARCHY_PATH/applications/foot.desktop" ~/.local/share/applications/
  cp -Rpf "$OMARCHY_PATH/applications/footclient.desktop" ~/.local/share/applications/
  cp -Rpf "$OMARCHY_PATH/applications/foot-server.desktop" ~/.local/share/applications/
fi

if [[ -f ~/.config/hypr/input.conf ]]; then
  sed -Ei 's/match:class \(Alacritty\|kitty\)/match:class (Alacritty|kitty|foot)/' ~/.config/hypr/input.conf
fi

if [[ -f ~/.config/hypr/apps/terminals.conf ]]; then
  sed -Ei 's/match:class \(Alacritty\|kitty\|com\.mitchellh\.ghostty\)/match:class (Alacritty|kitty|com.mitchellh.ghostty|foot)/' ~/.config/hypr/apps/terminals.conf
fi
