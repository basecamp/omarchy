#!/usr/bin/env bash

source ~/.config/omarchy/themes/nord/tmux/palettes/nord.sh

if [ ${#PALETTE[@]} -eq 0 ]; then
  echo "Warning: Nord palette not loaded. Colors may not display correctly."
fi

#+----------------+
#+ Plugin Support +
#+----------------+
#+--- tmux-prefix-highlight ---+
tmux set -g @prefix_highlight_fg "${PALETTE[black]}"
tmux set -g @prefix_highlight_bg "${PALETTE[cyan]}"

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
tmux set -g status-style "bg=${PALETTE[black]},fg=${PALETTE[white]}"

#+-------+
#+ Panes +
#+-------+
tmux set -g pane-border-style "bg=default,fg=${PALETTE[brightblack]}"
tmux set -g pane-active-border-style "bg=default,fg=${PALETTE[cyan]}"
tmux set -g display-panes-colour "${PALETTE[black]}"
tmux set -g display-panes-active-colour "${PALETTE[brightblack]}"

#+------------+
#+ Clock Mode +
#+------------+
tmux setw -g clock-mode-colour "${PALETTE[cyan]}"

#+----------+
#+ Messages +
#+---------+
tmux set -g message-style "bg=${PALETTE[bg_highlight]},fg=${PALETTE[cyan]}"
tmux set -g message-command-style "bg=${PALETTE[bg_highlight]},fg=${PALETTE[cyan]}"
