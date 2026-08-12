echo "Keep tmux clipboard copies working over mosh"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]]; then
  if ! grep -qF 'xterm*:Ms=\E]52;c;%p2%s\007' "$tmux_config"; then
    printf '\n%s\n' \
      '# Make OSC 52 clipboard writes compatible with mosh 1.4.' \
      'set -ag terminal-overrides ",xterm*:Ms=\E]52;c;%p2%s\007"' >>"$tmux_config"
  fi

  if ! grep -qF 'omarchy-tmux-osc52-copy' "$tmux_config"; then
    printf '%s\n' \
      'bind -N "Copy selection" -T copy-mode-vi y send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
      'bind -T copy-mode-vi Enter send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
      'bind -T copy-mode-vi MouseDragEnd1Pane send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
      'bind -T copy-mode-vi DoubleClick1Pane select-pane \; send -X select-word \; run-shell -d 0.3 \; send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
      'bind -T copy-mode-vi TripleClick1Pane select-pane \; send -X select-line \; run-shell -d 0.3 \; send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' >>"$tmux_config"
  fi

  if omarchy-cmd-present tmux && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$tmux_config" || true
  fi
fi
