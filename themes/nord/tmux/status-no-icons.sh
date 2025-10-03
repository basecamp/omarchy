#!/usr/bin/env bash

source ~/.config/omarchy/themes/nord/tmux/palettes/nord.sh

if [ ${#PALETTE[@]} -eq 0 ]; then
  echo "Warning: Nord palette not loaded. Colors may not display correctly."
fi

DATE_FORMAT=$(tmux show-environment -g THEME_DATE_FORMAT 2>/dev/null | cut -d= -f2-)
TIME_FORMAT=$(tmux show-environment -g THEME_TIME_FORMAT 2>/dev/null | cut -d= -f2-)

DATE_FORMAT=${DATE_FORMAT:-"%Y-%m-%d"}
TIME_FORMAT=${TIME_FORMAT:-"%H:%M"}

#+----------------+
#+ Plugin Support +
#+----------------+
#+--- tmux-prefix-highlight ---+
tmux set -g @prefix_highlight_output_prefix "#[fg=${PALETTE[cyan]}]#[bg=${PALETTE[black]}]#[nobold]#[noitalics]#[nounderscore]#[bg=${PALETTE[cyan]}]#[fg=${PALETTE[black]}]"
tmux set -g @prefix_highlight_output_suffix ""
tmux set -g @prefix_highlight_copy_mode_attr "fg=${PALETTE[cyan]},bg=${PALETTE[black]},bold"

#+--------+
#+ Status +
#+--------+
#+--- Bars ---+
tmux set -g status-left "#[fg=${PALETTE[black]},bg=${PALETTE[blue]},bold] #S #[fg=${PALETTE[blue]},bg=${PALETTE[black]},nobold,noitalics,nounderscore]"
tmux set -g status-right "#{prefix_highlight}#[fg=${PALETTE[brightblack]},bg=${PALETTE[black]},nobold,noitalics,nounderscore]#[fg=${PALETTE[white]},bg=${PALETTE[brightblack]}] ${DATE_FORMAT} #[fg=${PALETTE[white]},bg=${PALETTE[brightblack]},nobold,noitalics,nounderscore]#[fg=${PALETTE[white]},bg=${PALETTE[brightblack]}] ${TIME_FORMAT} #[fg=${PALETTE[cyan]},bg=${PALETTE[brightblack]},nobold,noitalics,nounderscore]#[fg=${PALETTE[black]},bg=${PALETTE[cyan]},bold] #H "

#+--- Windows ---+
tmux set -g window-status-format "#[fg=${PALETTE[black]},bg=${PALETTE[brightblack]},nobold,noitalics,nounderscore] #[fg=${PALETTE[white]},bg=${PALETTE[brightblack]}]#I #[fg=${PALETTE[white]},bg=${PALETTE[brightblack]},nobold,noitalics,nounderscore] #[fg=${PALETTE[white]},bg=${PALETTE[brightblack]}]#W #F #[fg=${PALETTE[brightblack]},bg=${PALETTE[black]},nobold,noitalics,nounderscore]"
tmux set -g window-status-current-format "#[fg=${PALETTE[black]},bg=${PALETTE[cyan]},nobold,noitalics,nounderscore] #[fg=${PALETTE[black]},bg=${PALETTE[cyan]}]#I #[fg=${PALETTE[black]},bg=${PALETTE[cyan]},nobold,noitalics,nounderscore] #[fg=${PALETTE[black]},bg=${PALETTE[cyan]}]#W #F #[fg=${PALETTE[cyan]},bg=${PALETTE[black]},nobold,noitalics,nounderscore]"
tmux set -g window-status-separator ""
