#!/usr/bin/env bash

source ~/.config/omarchy/themes/gruvbox/tmux/palettes/dark.sh

if [ ${#PALETTE[@]} -eq 0 ]; then
  echo "Warning: Gruvbox Dark palette not loaded. Colors may not display correctly."
fi

#+----------------+
#+ Plugin Support +
#+----------------+
#+--- tmux-prefix-highlight ---+
tmux set -g @prefix_highlight_fg "${PALETTE[bg]}"
tmux set -g @prefix_highlight_bg "${PALETTE[yellow_bright]}"

#+---------+
#+ Options +
#+---------+
tmux set -g status-interval 1
tmux set -g status on

#+--------+
#+ Status +
#+--------+
#+--- Layout ---+
tmux set -g status-justify left

#+--- Colors ---+
tmux set -g status-style "bg=${PALETTE[bg]},fg=${PALETTE[fg]}"

#+-------+
#+ Panes +
#+-------+
tmux set -g pane-border-style "bg=default,fg=${PALETTE[bg2]}"
tmux set -g pane-active-border-style "bg=default,fg=${PALETTE[yellow_bright]}"
tmux set -g display-panes-colour "${PALETTE[bg]}"
tmux set -g display-panes-active-colour "${PALETTE[bg2]}"

#+------------+
#+ Clock Mode +
#+------------+
tmux setw -g clock-mode-colour "${PALETTE[blue_bright]}"

#+----------+
#+ Messages +
#+---------+
tmux set -g message-style "bg=${PALETTE[bg_highlight]},fg=${PALETTE[yellow_bright]}"
tmux set -g message-command-style "bg=${PALETTE[bg_highlight]},fg=${PALETTE[yellow_bright]}"
