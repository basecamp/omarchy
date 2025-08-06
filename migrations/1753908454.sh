echo "Migrate from manually downloaded fonts to font packages"
if ! yay -Q ttf-cascadia-mono-nerd &>/dev/null; then
  yay -S --noconfirm ttf-cascadia-mono-nerd
  rm -rf ~/.local/share/fonts/Caskaydia*
  fc-cache
fi

if ! yay -Q ttf-ia-writer &>/dev/null; then
  yay -S --noconfirm ttf-ia-writer
  rm -rf ~/.local/share/fonts/iAWriterMonoS*
  fc-cache
fi
