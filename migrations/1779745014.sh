echo "Remove old Brave Origin Beta flags file and symlink Brave Origin flags to brave-flags.conf"

mkdir -p ~/.config
rm -f ~/.config/brave-origin-beta-flags.conf

if [[ -e ~/.config/brave-flags.conf ]]; then
  ln -sf ~/.config/brave-flags.conf ~/.config/brave-origin-flags.conf
fi
