# Status bar
set -g status-style "bg={{ background }},fg={{ foreground }}"

# Left: session name
set -g status-left "#[fg={{ background }},bg={{ accent }},bold] #S #[bg={{ background }}] "

# Right: hostname + prefix indicator
set -g status-right "#[fg={{ accent }}]#{?client_prefix,PREFIX ,}#[fg={{ color8 }}]#h "

# Window tabs
set -g window-status-format "#[fg={{ color8 }}] #I:#W "
set -g window-status-current-format "#[fg={{ accent }},bold] #I:#W "

# Pane borders
set -g pane-border-style "fg={{ color8 }}"
set -g pane-active-border-style "fg={{ accent }}"

# Messages
set -g message-style "bg={{ background }},fg={{ accent }}"
set -g message-command-style "bg={{ background }},fg={{ accent }}"

# Copy mode
set -g mode-style "bg={{ accent }},fg={{ background }}"

# Clock
setw -g clock-mode-colour "{{ accent }}"
