echo "Add cliamp music TUI player (Super+Shift+Alt+M)"

if omarchy-pkg-missing cliamp; then
  omarchy-pkg-add cliamp

  cp ~/.local/share/omarchy/applications/icons/Cliamp.png ~/.local/share/applications/icons/Cliamp.png
  gtk-update-icon-cache ~/.local/share/icons/hicolor &>/dev/null
  omarchy-tui-install "Cliamp" "cliamp" tile "$HOME/.local/share/applications/icons/Cliamp.png"

  if [[ -f ~/.config/hypr/bindings.conf ]] && ! grep -q "cliamp" ~/.config/hypr/bindings.conf; then
    sed -i '/^bindd = SUPER SHIFT, M, Music, exec, omarchy-launch-or-focus spotify/a bindd = SUPER SHIFT ALT, M, Music TUI, exec, omarchy-launch-or-focus-tui cliamp' ~/.config/hypr/bindings.conf
  fi
fi
