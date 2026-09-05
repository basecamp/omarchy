echo "Add iron.nvim REPL configuration to Neovim"

nvim_config_dir="$HOME/.config/nvim"
iron_target="$nvim_config_dir/lua/plugins/iron.lua"
iron_source="/usr/share/omarchy-nvim/config/lua/plugins/iron.lua"

# Skip if the user already has their own iron.lua. If the packaged source is
# not installed yet, let install fail so the migration retries next run
# instead of being marked done.
if [[ -d $nvim_config_dir && ! -f $iron_target ]]; then
  mkdir -p "$(dirname "$iron_target")"
  install -m 0644 "$iron_source" "$iron_target"
fi
