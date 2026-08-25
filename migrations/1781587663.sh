echo "Enable secure remote Neovim clipboard support"

nvim_config_dir="$HOME/.config/nvim"
nvim_options="$nvim_config_dir/lua/config/options.lua"
nvim_provider="$nvim_config_dir/lua/config/remote_clipboard.lua"

provider_source="${OMARCHY_NVIM_REMOTE_CLIPBOARD:-/usr/share/omarchy-nvim/config/lua/config/remote_clipboard.lua}"

# The provider ships in omarchy-nvim, a package a user running their own Neovim
# config can drop, so its absence is normal and not a reason to abort. Bailing
# out here would take the migration queue and the rest of the update with it.
if [[ -d $nvim_config_dir && -f $provider_source ]]; then
  mkdir -p "$(dirname "$nvim_provider")"
  install -m 0644 "$provider_source" "$nvim_provider"

  if [[ -f $nvim_options ]] && ! grep -qF 'config.remote_clipboard' "$nvim_options"; then
    tmp=$(mktemp)
    {
      printf '%s\n' 'require("config.remote_clipboard").setup()'
      cat "$nvim_options"
    } >"$tmp"
    mv "$tmp" "$nvim_options"
  fi
fi

tmux_config="$HOME/.config/tmux/tmux.conf"
if [[ -f $tmux_config ]] && ! grep -Eq '(^|[[:space:],"])\*:clipboard([[:space:]",]|$)' "$tmux_config"; then
  printf '\n# Enable OSC 52 clipboard forwarding for remote Neovim yanks.\nset -as terminal-features ",*:clipboard"\n' >>"$tmux_config"
fi
