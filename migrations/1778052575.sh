echo "Enable extended keyboard support in tmux"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]] && ! grep -qxF "set -g extended-keys on" "$tmux_config"; then
  sed -i '/^set -g detach-on-destroy off$/a set -g extended-keys on\nset -g extended-keys-format csi-u\nset -sg escape-time 10' "$tmux_config"
fi
