echo "Add persistent Tmux workspaces"

omarchy-pkg-add tmux-resurrect

tmux_config="$HOME/.config/tmux/tmux.conf"
[[ -f $tmux_config ]] || exit 0
grep -Fq '# Persistent workspaces' "$tmux_config" || cat >>"$tmux_config" <<'EOF'

# Persistent workspaces
set -g @resurrect-dir '~/.local/state/omarchy/tmux/resurrect'
run-shell /usr/share/tmux-resurrect/resurrect.tmux
set-hook -g session-created[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g session-closed[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g window-linked[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g window-unlinked[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g after-split-window[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g after-kill-pane[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g after-rename-session[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g after-rename-window[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g after-select-layout[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set-hook -g client-detached[100] 'run-shell -b "/usr/bin/omarchy-tmux-resurrect-save"'
set -g @resurrect-hook-pre-restore-all 'tmux set-option -g @omarchy-resurrect-restoring 1'
set -g @resurrect-hook-post-restore-all 'tmux set-option -gu @omarchy-resurrect-restoring; /usr/bin/omarchy-tmux-resurrect-save'
EOF

omarchy-restart-tmux
