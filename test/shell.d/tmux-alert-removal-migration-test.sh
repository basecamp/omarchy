#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1785189600.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# Everything the migration reaches for is stubbed: a real tmux here would talk
# to the developer's own server.
cat >"$test_dir/bin/tmux" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$TMUX_CALLS"

case "$1" in
  has-session) exit "${TMUX_SERVER_MISSING:-0}" ;;
  show-hooks)
    cat <<'HOOKS'
after-select-window[0] run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"
alert-activity
alert-bell[0] run-shell -b "omarchy-shell -q omarchy.indicators refresh"
client-focus-in[100] run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"
client-focus-out[42] display-message "user hook"
session-created
HOOKS
    ;;
  list-windows) printf '@0\n@3\n' ;;
esac
STUB

cat >"$test_dir/bin/omarchy-restart-tmux" <<'STUB'
#!/bin/bash

echo restart >>"$TMUX_RESTARTS"
STUB

cat >"$test_dir/bin/omarchy-restart-shell" <<'STUB'
#!/bin/bash

echo restart >>"$SHELL_RESTARTS"
exit "${SHELL_RESTART_STATUS:-0}"
STUB

cat >"$test_dir/bin/omarchy-state" <<'STUB'
#!/bin/bash

printf '%s\n' "$*" >>"$STATE_CALLS"
STUB

chmod +x "$test_dir/bin/"*

export TMUX_CALLS="$test_dir/tmux-calls"
export TMUX_RESTARTS="$test_dir/tmux-restarts"
export SHELL_RESTARTS="$test_dir/shell-restarts"
export STATE_CALLS="$test_dir/state-calls"

home="$test_dir/home"
tmux_config="$home/.config/tmux/tmux.conf"
shell_config="$home/.config/omarchy/shell.json"

run_migration() {
  : >"$TMUX_CALLS"
  : >"$TMUX_RESTARTS"
  : >"$SHELL_RESTARTS"
  : >"$STATE_CALLS"

  HOME="$home" PATH="$test_dir/bin:$PATH" bash -euo pipefail "$migration" >/dev/null
}

reset_home() {
  rm -rf "$home"
  mkdir -p "$home/.config/tmux" "$home/.config/omarchy"
}

# ---------------------------------------------------------------- tmux config

# The shipped config with the alert block put back is exactly what an installed
# machine has, so cleaning it has to land on the shipped config byte for byte.
reset_home
awk '
  /^# Status bar$/ {
    print "# Alerts"
    print "set-hook -g alert-bell '\''run-shell -b \"omarchy-shell -q omarchy.indicators refresh\"'\''"
    print "set-hook -g alert-activity '\''run-shell -b \"omarchy-shell -q omarchy.indicators refresh\"'\''"
    print "set-hook -g alert-silence '\''run-shell -b \"omarchy-shell -q omarchy.indicators refresh\"'\''"
    print "set-hook -g after-select-window '\''run-shell -b \"omarchy-tmux-alert track #{window_id} #{window_activity}\"'\''"
    print "set-hook -g client-session-changed '\''run-shell -b \"omarchy-tmux-alert track #{window_id} #{window_activity}\"'\''"
    print "set-hook -g client-focus-out[100] '\''run-shell -b \"omarchy-tmux-alert track #{window_id} #{window_activity}\"'\''"
    print "set-hook -g client-focus-in[100] '\''run-shell -b \"omarchy-tmux-alert track #{window_id} #{window_activity}\"'\''"
    print ""
  }
  { print }
' "$ROOT/config/tmux/tmux.conf" >"$tmux_config"

run_migration

diff -u "$ROOT/config/tmux/tmux.conf" "$tmux_config" >/dev/null ||
  fail "alert removal restores the shipped tmux config" "$(diff -u "$ROOT/config/tmux/tmux.conf" "$tmux_config")"
pass "alert removal restores the shipped tmux config"

(($(wc -l <"$TMUX_RESTARTS") == 1)) || fail "alert removal reloads tmux once"
pass "alert removal reloads tmux once"

before=$(sha256sum "$tmux_config")
run_migration
[[ $before == $(sha256sum "$tmux_config") ]] || fail "alert removal is idempotent"
[[ ! -s $TMUX_RESTARTS ]] || fail "idempotent alert removal does not reload tmux"
pass "alert removal is idempotent"

# The hooks the removed migrations appended sit at the end of the file, and a
# user's own hooks and blank lines have to survive next to them.
reset_home
cat >"$tmux_config" <<'EOF'
set -g mouse on


# Custom
set-hook -g alert-bell 'display-message "mine"'
set-hook -g client-focus-out[42] 'display-message "custom focus hook"'

# Alerts
set-hook -g alert-bell 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g alert-activity 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
set-hook -g after-select-window 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
  set-hook -g client-session-changed 'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'
set-hook -g client-focus-out[100] 'run-shell -b "omarchy-tmux-alert track #{window_id} #{window_activity}"'
EOF

run_migration

expected=$(printf '%s\n' 'set -g mouse on' '' '' '# Custom' "set-hook -g alert-bell 'display-message \"mine\"'" "set-hook -g client-focus-out[42] 'display-message \"custom focus hook\"'")
[[ $(cat "$tmux_config") == "$expected" ]] ||
  fail "alert removal drops an appended block and keeps the user's lines" "$(cat -A "$tmux_config")"
pass "alert removal drops an appended block and keeps the user's lines"

# An older config kept the refresh spelling of these two hooks; an indented one
# is still the hook Omarchy wrote.
grep -q 'after-select-window\|client-session-changed' "$tmux_config" &&
  fail "alert removal drops the older and indented hook spellings"
pass "alert removal drops the older and indented hook spellings"

# A config that never had the feature is not a config to rewrite.
reset_home
printf '%s\n' 'set -g mouse on' '' '' 'set -g status-position top' '' >"$tmux_config"
before=$(sha256sum "$tmux_config")
run_migration
[[ $before == $(sha256sum "$tmux_config") ]] || fail "alert removal leaves an unrelated config alone" "$(cat -A "$tmux_config")"
[[ ! -s $TMUX_RESTARTS ]] || fail "alert removal does not reload tmux for an unrelated config"
pass "alert removal leaves an unrelated config alone"

# Dotfile setups symlink the config; the link has to survive the rewrite.
reset_home
mkdir -p "$home/dotfiles"
cat >"$home/dotfiles/tmux.conf" <<'EOF'
set -g mouse on

# Alerts
set-hook -g alert-bell 'run-shell -b "omarchy-shell -q omarchy.indicators refresh"'
EOF
ln -sf "$home/dotfiles/tmux.conf" "$tmux_config"

run_migration

[[ -L $tmux_config ]] || fail "alert removal writes through a symlinked config"
[[ $(readlink "$tmux_config") == "$home/dotfiles/tmux.conf" ]] || fail "alert removal keeps the symlink target"
grep -q 'alert-bell' "$home/dotfiles/tmux.conf" && fail "alert removal cleans the symlink target"
pass "alert removal writes through a symlinked config"

# --------------------------------------------------------------- live server

reset_home
run_migration

grep -Fxq 'set-hook -gu after-select-window[0]' "$TMUX_CALLS" || fail "alert removal unsets live hooks by index" "$(cat "$TMUX_CALLS")"
grep -Fxq 'set-hook -gu alert-bell[0]' "$TMUX_CALLS" || fail "alert removal unsets live alert hooks"
grep -Fxq 'set-hook -gu client-focus-in[100]' "$TMUX_CALLS" || fail "alert removal unsets live focus hooks"
grep -q 'set-hook -gu client-focus-out\[42\]' "$TMUX_CALLS" && fail "alert removal keeps a user's hook at another index"
pass "alert removal unsets the live hooks it installed"

grep -Fxq 'set-option -wqu -t @0 @omarchy_unfocused_activity' "$TMUX_CALLS" || fail "alert removal clears tracked window options"
grep -Fxq 'set-option -wqu -t @3 @omarchy_unfocused_activity' "$TMUX_CALLS" || fail "alert removal clears every tracked window"
pass "alert removal clears the window options it stamped"

TMUX_SERVER_MISSING=1 run_migration
grep -q 'set-hook' "$TMUX_CALLS" && fail "alert removal skips a server that is not running" "$(cat "$TMUX_CALLS")"
pass "alert removal skips a server that is not running"

# ---------------------------------------------------------------- shell.json

reset_home
cat >"$shell_config" <<'EOF'
{
  "bar": {
    "layout": {
      "left": [
        { "id": "omarchy.indicators", "items": ["TmuxAlert", "Dnd", { "id": "TmuxAlert" }, { "id": "NightLight" }] }
      ],
      "center": [
        { "id": "omarchy.indicators", "items": ["TmuxAlert"] },
        { "id": "omarchy.clock" }
      ],
      "right": [
        { "id": "omarchy.indicators", "indicators": ["TmuxAlert", "Dnd"] },
        { "id": "omarchy.indicators", "items": [] }
      ]
    }
  }
}
EOF

run_migration

grep -q 'TmuxAlert' "$shell_config" && fail "alert removal strips TmuxAlert from shell.json" "$(cat "$shell_config")"
pass "alert removal strips TmuxAlert from shell.json"

[[ $(jq -c '.bar.layout.left[0].items' "$shell_config") == '["Dnd",{"id":"NightLight"}]' ]] ||
  fail "alert removal keeps the other picked indicators" "$(jq -c '.bar.layout.left[0].items' "$shell_config")"
pass "alert removal keeps the other picked indicators"

[[ $(jq -c '[.bar.layout.center[].id]' "$shell_config") == '["omarchy.clock"]' ]] ||
  fail "alert removal drops a widget left with nothing to show" "$(jq -c '.bar.layout.center' "$shell_config")"
pass "alert removal drops a widget left with nothing to show"

[[ $(jq -c '.bar.layout.right[0].indicators' "$shell_config") == '["Dnd"]' ]] ||
  fail "alert removal handles the older indicators key" "$(jq -c '.bar.layout.right[0]' "$shell_config")"
pass "alert removal handles the older indicators key"

[[ $(jq -c '.bar.layout.right[1]' "$shell_config") == '{"id":"omarchy.indicators","items":[]}' ]] ||
  fail "alert removal leaves an already-empty list alone" "$(jq -c '.bar.layout.right[1]' "$shell_config")"
pass "alert removal leaves an already-empty list alone"

# The running shell hot-reloads shell.json and the post-update restart is
# unconditional, so the migration itself never touches the shell.
[[ ! -s $SHELL_RESTARTS ]] || fail "alert removal leaves shell restarts to the update" "$(cat "$SHELL_RESTARTS")"
[[ ! -s $STATE_CALLS ]] || fail "alert removal defers no shell restart" "$(cat "$STATE_CALLS")"
pass "alert removal leaves shell restarts to the update"
