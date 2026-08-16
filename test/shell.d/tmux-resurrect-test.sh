#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

config="$ROOT/config/tmux/tmux.conf"
save_command='/usr/bin/omarchy-tmux-resurrect-save'

grep -Fx "set -g @resurrect-dir '~/.local/state/omarchy/tmux/resurrect'" "$config" >/dev/null ||
  fail "tmux resurrect stores snapshots in Omarchy state"
grep -Fx 'run-shell /usr/share/tmux-resurrect/resurrect.tmux' "$config" >/dev/null ||
  fail "tmux loads the packaged resurrection plugin"
grep -F '@resurrect-capture-pane-contents' "$config" >/dev/null &&
  fail "tmux resurrection does not persist pane contents by default"

for hook in \
  session-created session-closed window-linked window-unlinked after-split-window \
  after-kill-pane after-rename-session after-rename-window after-select-layout \
  client-detached; do
  grep -Fx "set-hook -g $hook[100] 'run-shell -b \"$save_command\"'" "$config" >/dev/null ||
    fail "tmux saves after $hook"
done
pass "tmux saves workspace changes without continuum"

grep -Fx "set -g @resurrect-hook-pre-restore-all 'tmux set-option -g @omarchy-resurrect-restoring 1'" "$config" >/dev/null ||
  fail "tmux suppresses snapshots during restoration"
grep -Fx "set -g @resurrect-hook-post-restore-all 'tmux set-option -gu @omarchy-resurrect-restoring; $save_command'" "$config" >/dev/null ||
  fail "tmux saves once restoration finishes"
pass "tmux restoration never snapshots a partial layout"

test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

test_bin="$test_dir/bin"
plugin_dir="$test_dir/tmux-resurrect"
tmux_log="$test_dir/tmux.log"
plugin_log="$test_dir/plugin.log"
test_config="$test_dir/tmux.conf"
socket="$test_dir/tmux.sock"

mkdir -p "$test_bin" "$plugin_dir/scripts"

cat >"$plugin_dir/resurrect.tmux" <<'EOF'
#!/bin/bash
EOF
chmod +x "$plugin_dir/resurrect.tmux"

while IFS= read -r line || [[ -n $line ]]; do
  printf '%s\n' "${line//\/usr\/share\/tmux-resurrect/$plugin_dir}"
done <"$config" >"$test_config"

tmux -S "$socket" -f /dev/null new-session -d -s test
tmux -S "$socket" source-file "$test_config"
tmux -S "$socket" show-hooks -g session-created | grep -Fq "$save_command" ||
  fail "tmux accepts the resurrection hook configuration"
tmux -S "$socket" kill-server
pass "tmux loads resurrection hooks without replacing other configuration"

cat >"$test_bin/tmux" <<'EOF'
#!/bin/bash

printf '%s\n' "$*" >>"$TMUX_LOG"

case "$1" in
  has-session)
    exit 0
    ;;
  show-options)
    [[ ${TMUX_RESTORING:-0} == "1" ]] && printf '1\n'
    ;;
esac
EOF
chmod +x "$test_bin/tmux"

cat >"$plugin_dir/scripts/save.sh" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$TMUX_PLUGIN_LOG"
EOF
chmod +x "$plugin_dir/scripts/save.sh"

run_save() {
  PATH="$test_bin:$PATH" \
    HOME="$test_dir/home" \
    XDG_RUNTIME_DIR="$test_dir/runtime" \
    TMUX_RESURRECT_PATH="$plugin_dir" \
    TMUX_LOG="$tmux_log" \
    TMUX_PLUGIN_LOG="$plugin_log" \
    "$ROOT/bin/omarchy-tmux-resurrect-save"
}

run_save
[[ $(<"$plugin_log") == 'quiet' ]] || fail "tmux hook uses upstream quiet save"
pass "tmux saves through the packaged resurrection engine"

: >"$plugin_log"
TMUX_RESTORING=1 run_save
[[ ! -s $plugin_log ]] || fail "tmux skips snapshots while restoration is active"
pass "tmux does not overwrite a snapshot during restoration"
