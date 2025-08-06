echo "Add hyprsunset blue light filter"
if ! command -v hyprsunset &>/dev/null; then
  yay -S --noconfirm --needed hyprsunset
fi

~/.local/share/omarchy/bin/omarchy-refresh-hyprsunset
