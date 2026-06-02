echo "Remove old Brave Origin Beta flags file (renamed to brave-origin)"

if [[ -L ~/.config/brave-origin-beta-flags.conf ]]; then
  rm -f ~/.config/brave-origin-beta-flags.conf
fi

if [[ -e ~/.config/brave-origin-beta-flags.conf ]]; then
  rm -f ~/.config/brave-origin-beta-flags.conf
fi
