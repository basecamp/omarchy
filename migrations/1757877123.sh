echo "Obsidian should be using Wayland IME for better compatibility with fcitx5 and other languages"

if [[ -f ~/.config/hypr/bindings.conf ]]; then
  sed -i '/^bindd = SUPER, O, Obsidian, exec, uwsm app -- obsidian -disable-gpu/{
    /--enable-wayland-ime/! s/$/ --enable-wayland-ime/
  }' ~/.config/hypr/bindings.conf
fi
