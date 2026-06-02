echo "Remove old Brave Origin Beta flags file and symlink Brave Origin flags to brave-flags.conf"

mkdir -p ~/.config
rm -f ~/.config/brave-origin-beta-flags.conf

if [[ ! -e ~/.config/brave-origin-flags.conf ]]; then
  ln -s ~/.config/brave-flags.conf ~/.config/brave-origin-flags.conf
fi
