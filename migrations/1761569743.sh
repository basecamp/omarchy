echo "Add default Ctrl+P binding for imv; backup existing config if present"

if [ -f ~/.config/imv/config ]; then
  cp ~/.config/imv/config ~/.config/imv/config.bak.$(date +%s)
else
  mkdir -p ~/.config/imv
fi

cp ~/.local/share/omarchy/config/imv/config ~/.config/imv/config
