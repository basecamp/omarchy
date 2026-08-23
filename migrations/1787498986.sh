echo "Add iron.nvim REPL configuration to Neovim"

nvim_config_dir="$HOME/.config/nvim"
iron_target="$nvim_config_dir/lua/plugins/iron.lua"
iron_source="/usr/share/omarchy-nvim/config/lua/plugins/iron.lua"

if [[ -d $nvim_config_dir && -f $iron_source ]]; then
  mkdir -p "$(dirname "$iron_target")"
  install -m 0644 "$iron_source" "$iron_target"
fi
