#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1784955584.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/home/.config/tmux" "$test_dir/bin"

cat >"$test_dir/home/.config/tmux/tmux.conf" <<'EOF'
# Alerts
set-hook -g alert-bell 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g after-select-window 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g client-session-changed 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g client-focus-out[42] 'display-message "custom focus hook"'
EOF

cat >"$test_dir/bin/omarchy-restart-tmux" <<'EOF'
#!/bin/bash

echo restart >>"$TMUX_MIGRATION_RESTART_LOG"
EOF
chmod +x "$test_dir/bin/omarchy-restart-tmux"

export TMUX_MIGRATION_RESTART_LOG="$test_dir/restarts"
tmux_config="$test_dir/home/.config/tmux/tmux.conf"

HOME="$test_dir/home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null

grep -Fq 'after-select-window '"'"'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'"'" "$tmux_config" ||
  fail "tmux activity migration tracks newly selected windows"
grep -Fq 'client-session-changed '"'"'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'"'" "$tmux_config" ||
  fail "tmux activity migration tracks session changes"
grep -Fq 'client-focus-out[100] '"'"'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'"'" "$tmux_config" ||
  fail "tmux activity migration tracks terminal focus loss"
grep -Fq 'client-focus-in[100] '"'"'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'"'" "$tmux_config" ||
  fail "tmux activity migration tracks terminal focus gain"
grep -Fq 'client-focus-out[42] '"'"'display-message "custom focus hook"'"'" "$tmux_config" ||
  fail "tmux activity migration preserves custom indexed focus hooks"
restart_count=$(wc -l <"$TMUX_MIGRATION_RESTART_LOG")
((restart_count == 1)) || fail "tmux activity migration reloads tmux once"
pass "tmux activity migration installs focus-aware hooks"

before=$(sha256sum "$tmux_config")
HOME="$test_dir/home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
after=$(sha256sum "$tmux_config")

[[ $before == "$after" ]] || fail "tmux activity migration is idempotent"
restart_count=$(wc -l <"$TMUX_MIGRATION_RESTART_LOG")
((restart_count == 1)) || fail "idempotent tmux activity migration does not reload tmux"
pass "tmux activity migration is idempotent"
