#!/bin/bash
sudo pacman -S --noconfirm --needed keepassxc syncthing \
  nodejs npm tree-sitter-cli unzip qbittorrent ollama \
  python-json5 python-pywal fcitx5-configtool \
  hplip baobab android-file-transfer gthumb nemo nemo-fileroller \
  gnome-disk-utility nautilus \
  nwg-look inkscape gnumeric


yay -S --noconfirm --needed \
  brightnessctl playerctl pamixer wiremix wireplumber \
  fcitx5 fcitx5-gtk fcitx5-qt wl-clip-persist \
  ffmpegthumbnailer python-pywalfox \
  slurp satty \
  mpv xreader imv \
  zen-browser-bin chromium video-downloader

# load nemo defaults
dconf load /org/nemo/ < ~/.local/share/autarky/default/nemo.dconf

# Add screen recorder based on GPU
if lspci | grep -qi 'nvidia'; then
  yay -S --noconfirm --needed wf-recorder
else
  yay -S --noconfirm --needed wl-screenrec
fi
