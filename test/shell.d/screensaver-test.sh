#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

terminal_pids=()
unrelated_pid=

cleanup() {
  local pid

  for pid in "${terminal_pids[@]}" ${unrelated_pid:-}; do
    kill -KILL "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  pkill -x omarchy-saver 2>/dev/null || true
  rm -rf "$tmpdir"
}
trap cleanup EXIT

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "${LOCKED:-false}"
SH

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
[[ $* == "activewindow -j" ]] && printf '{"class":"org.omarchy.screensaver"}\n'
SH

cat >"$mock_bin/jq" <<'SH'
#!/bin/bash
cat >/dev/null
exit 0
SH

cat >"$mock_bin/stty" <<'SH'
#!/bin/bash
printf '30 100\n'
SH

cat >"$mock_bin/ttfx" <<'SH'
#!/bin/bash

if [[ ${1:-} == "--unrelated" ]]; then
  trap 'printf "unrelated-term\n" >>"$CALL_LOG"; exit 0' TERM
  printf 'unrelated-start\n' >>"$CALL_LOG"
elif [[ ${SAVER_MODE:-} == "ignore-term" ]]; then
  trap '' TERM
  printf 'renderer-%s-start\n' "$SAVER_LABEL" >>"$CALL_LOG"
else
  trap 'printf "renderer-%s-term\n" "$SAVER_LABEL" >>"$CALL_LOG"; sleep 0.15; printf "renderer-%s-exit\n" "$SAVER_LABEL" >>"$CALL_LOG"; exit 0' TERM
  printf 'renderer-%s-start\n' "$SAVER_LABEL" >>"$CALL_LOG"
fi

while true; do
  sleep 0.02
done
SH

chmod +x "$mock_bin"/*

wait_for_count() {
  local pattern="$1"
  local expected="$2"
  local description="$3"
  local attempt count

  for ((attempt = 0; attempt < 300; attempt++)); do
    count=$(rg -c "$pattern" "$call_log" 2>/dev/null || true)
    [[ ${count:-0} == "$expected" ]] && return
    sleep 0.01
  done

  fail "$description" "calls: $(cat "$call_log" 2>/dev/null || true)"
}

wait_for_exit() {
  local pid="$1"
  local description="$2"
  local attempt

  for ((attempt = 0; attempt < 300; attempt++)); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.01
  done

  fail "$description" "process $pid is still running"
}

line_number() {
  rg -n "^$1$" "$call_log" | cut -d: -f1
}

run_screensaver() {
  local label="$1"
  local mode="${2:-normal}"

  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" SAVER_LABEL="$label" SAVER_MODE="$mode" \
    "$ROOT/bin/omarchy-screensaver" < <(sleep 10) >/dev/null 2>&1
  printf 'terminal-%s-exit\n' "$label" >>"$call_log"
}

PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$mock_bin/ttfx" --unrelated &
unrelated_pid=$!

run_screensaver a &
terminal_pids+=("$!")
run_screensaver b &
terminal_pids+=("$!")

wait_for_count '^renderer-[ab]-start$' 2 "both screensaver renderers start"
wait_for_count '^unrelated-start$' 1 "the unrelated ttfx starts"

mapfile -t supervisors < <(pgrep -x omarchy-saver)
(( ${#supervisors[@]} == 2 )) ||
  fail "each screensaver has a named supervisor" "pids: ${supervisors[*]}"

# A signal delivered to one monitor must coordinate shutdown across all monitors.
kill -TERM "${supervisors[0]}"

for pid in "${terminal_pids[@]}"; do
  wait_for_exit "$pid" "screensaver terminal exits after its renderer"
  wait "$pid"
done
terminal_pids=()

kill -0 "$unrelated_pid" 2>/dev/null ||
  fail "screensaver shutdown leaves unrelated ttfx processes alone"
[[ $(rg -c '^renderer-[ab]-start$' "$call_log") == "2" ]] ||
  fail "screensaver supervisors do not respawn renderers during shutdown" "calls: $(cat "$call_log")"

for label in a b; do
  term_line=$(line_number "renderer-$label-term")
  renderer_exit_line=$(line_number "renderer-$label-exit")
  terminal_exit_line=$(line_number "terminal-$label-exit")

  (( term_line < renderer_exit_line && renderer_exit_line < terminal_exit_line )) ||
    fail "screensaver $label reaps its renderer before the terminal exits" "calls: $(cat "$call_log")"
done
pass "screensaver supervisors reap only their own renderers before exiting"

run_screensaver stubborn ignore-term &
terminal_pids+=("$!")
wait_for_count '^renderer-stubborn-start$' 1 "the stubborn renderer starts"

mapfile -t supervisors < <(pgrep -x omarchy-saver)
(( ${#supervisors[@]} == 1 )) ||
  fail "the stubborn renderer has one supervisor" "pids: ${supervisors[*]}"
kill -TERM "${supervisors[0]}"
wait_for_exit "${terminal_pids[0]}" "a renderer ignoring SIGTERM is stopped within the grace period"
wait "${terminal_pids[0]}"
terminal_pids=()

[[ -z $(rg '^renderer-stubborn-exit$' "$call_log" || true) ]] ||
  fail "the stubborn renderer requires forced termination" "calls: $(cat "$call_log")"
pass "screensaver supervisor bounds renderer shutdown"

before=$(rg -c '^renderer-.*-start$' "$call_log")
PATH="$mock_bin:$PATH" CALL_LOG="$call_log" SAVER_LABEL=locked LOCKED=true \
  "$ROOT/bin/omarchy-screensaver" </dev/null >/dev/null 2>&1
after=$(rg -c '^renderer-.*-start$' "$call_log")
[[ $after == "$before" ]] ||
  fail "a screensaver starting during lock does not launch ttfx" "calls: $(cat "$call_log")"
pass "screensaver does not start a renderer while locked"

kill -TERM "$unrelated_pid"
wait "$unrelated_pid"
unrelated_pid=
