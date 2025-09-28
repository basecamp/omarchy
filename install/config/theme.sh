OMARCHY_DESCRIPTION="Theme"

omarchy_install() {
  # Set links for Nautilius action icons
  sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
  sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg

  # Setup theme links
  mkdir -p ~/.config/omarchy/themes
  for f in ~/.local/share/omarchy/themes/*; do ln -nfs "$f" ~/.config/omarchy/themes/; done

  # Set initial theme
  mkdir -p ~/.config/omarchy/current
  ln -snf ~/.config/omarchy/themes/tokyo-night ~/.config/omarchy/current/theme
  ln -snf ~/.config/omarchy/current/theme/backgrounds/1-scenery-pink-lakeside-sunset-lake-landscape-scenic-panorama-7680x3215-144.png ~/.config/omarchy/current/background

  # Set specific app links for current theme
  ln -snf ~/.config/omarchy/current/theme/neovim.lua ~/.config/nvim/lua/plugins/theme.lua

  mkdir -p ~/.config/btop/themes
  ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme

  mkdir -p ~/.config/mako
  ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config

  mkdir -p ~/.config/eza
  ln -snf ~/.config/omarchy/current/theme/eza.yml ~/.config/eza/theme.yml

  # Add managed policy directories for Chromium and Brave for theme changes
  sudo mkdir -p /etc/chromium/policies/managed
  sudo chmod a+rw /etc/chromium/policies/managed

  sudo mkdir -p /etc/brave/policies/managed
  sudo chmod a+rw /etc/brave/policies/managed
}

omarchy_verify() {
  [[ -d ~/.config/omarchy/themes ]] || add_error "Theme directory missing: ~/.config/omarchy/themes"
  [[ -L ~/.config/omarchy/current/theme ]] || add_error "Current theme symlink missing"
  [[ -L ~/.config/omarchy/current/background ]] || add_error "Background symlink missing"

  [[ -L /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg ]] || add_error "Nautilus previous icon not linked"
  [[ -L /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg ]] || add_error "Nautilus next icon not linked"

  [[ -L ~/.config/nvim/lua/plugins/theme.lua ]] || add_error "Neovim theme link missing"
  [[ -L ~/.config/btop/themes/current.theme ]] || add_error "btop theme link missing"
  [[ -L ~/.config/mako/config ]] || add_error "mako config link missing"
  [[ -L ~/.config/eza/theme.yml ]] || add_error "eza theme link missing"

  [[ -d /etc/chromium/policies/managed ]] || add_error "Chromium policy directory missing"
  [[ -d /etc/brave/policies/managed ]] || add_error "Brave policy directory missing"
}
