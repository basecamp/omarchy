echo "Keep tmux clipboard copies working over mosh"

tmux_config="$HOME/.config/tmux/tmux.conf"

if [[ -f $tmux_config ]]; then
  mosh_override='set -ag terminal-overrides ",xterm*:Ms=\\E]52;c;%p2%s\\007"'
  if ! grep -qFx "$mosh_override" "$tmux_config"; then
    printf '\n%s\n' \
      '# Make OSC 52 clipboard writes compatible with mosh 1.4.' \
      "$mosh_override" >>"$tmux_config"
  fi

  stock_copy_binding='bind -N "Copy selection" -T copy-mode-vi y send -X copy-selection-and-cancel'
  if grep -qFx "$stock_copy_binding" "$tmux_config" && ! grep -qF 'omarchy-tmux-osc52-copy' "$tmux_config"; then
    tmp=$(mktemp)
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line == "$stock_copy_binding" ]]; then
        printf '%s\n' \
          'bind -N "Copy selection" -T copy-mode-vi y send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
          'bind -T copy-mode-vi Enter send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
          'bind -T copy-mode-vi MouseDragEnd1Pane send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
          'bind -T copy-mode-vi DoubleClick1Pane select-pane \; send -X select-word \; run-shell -d 0.3 \; send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"' \
          'bind -T copy-mode-vi TripleClick1Pane select-pane \; send -X select-line \; run-shell -d 0.3 \; send -FX copy-pipe-and-cancel "omarchy-tmux-osc52-copy '\''#{client_tty}'\''"'
      else
        printf '%s\n' "$line"
      fi
    done <"$tmux_config" >"$tmp"
    cat "$tmp" >"$tmux_config"
    rm -f "$tmp"
  fi

  if omarchy-cmd-present tmux && tmux list-sessions >/dev/null 2>&1; then
    tmux source-file "$tmux_config" || true
  fi
fi
