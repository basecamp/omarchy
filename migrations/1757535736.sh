echo "Enabling vim keys in btop"

CONFIG_FILE=~/.config/btop/btop.conf

if [[ -f $CONFIG_FILE ]]; then
  if grep -q "^vim_keys = " "$CONFIG_FILE"; then
    sed -i 's/^vim_keys = False/vim_keys = True/' "$CONFIG_FILE"
  fi
fi
