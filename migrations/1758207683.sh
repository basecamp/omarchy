echo "Copy configs for keepassxc as alternative password manager options"

if [[ ! -f ~/.config/keepassxc/keepassxc.ini ]]; then
  mkdir -p ~/.config/keepassxc/
  cp -Rpf $OMARCHY_PATH/config/keepassxc/keepassxc.ini ~/.config/keepassxc/keepassxc.ini
fi
