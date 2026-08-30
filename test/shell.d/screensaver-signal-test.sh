#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
stub_dir="$test_tmp/bin"
running_pid=

cleanup() {
  if [[ -n $running_pid ]] && kill -0 "$running_pid" 2>/dev/null; then
    kill -KILL "$running_pid" 2>/dev/null || true
    wait "$running_pid" 2>/dev/null || true
  fi

  rm -rf "$test_tmp"
}
trap cleanup EXIT

mkdir -p "$stub_dir"

cat >"$stub_dir/hyprctl" <<'STUB'
#!/bin/bash

if [[ $* == "activewindow -j" ]]; then
  printf '{"class":"org.omarchy.screensaver"}\n'
elif [[ $* == *"invisible = false"* ]]; then
  printf 'cleanup\n' >>"$SCREENSAVER_TEST_LOG"

  # Model the terminal teardown sending SIGHUP while cleanup is still inside
  # its first external command. One nested signal is enough to expose whether
  # the handler disarmed before entering exit_screensaver.
  if mkdir "$SCREENSAVER_TEST_STATE/signal-sent" 2>/dev/null; then
    kill -HUP "$PPID"
  fi
fi
STUB

cat >"$stub_dir/ttfx" <<'STUB'
#!/bin/bash
printf 'ready\n' >>"$SCREENSAVER_TEST_LOG"
STUB

cat >"$stub_dir/tty" <<'STUB'
#!/bin/bash
printf '/dev/pts/999\n'
STUB

cat >"$stub_dir/stty" <<'STUB'
#!/bin/bash
printf '30 100\n'
STUB

cat >"$stub_dir/pgrep" <<'STUB'
#!/bin/bash
exit 0
STUB

cat >"$stub_dir/pkill" <<'STUB'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$SCREENSAVER_TEST_LOG"
STUB

chmod +x "$stub_dir"/*

wait_for_log() {
  local pattern="$1" log="$2" attempt

  for attempt in {1..200}; do
    grep -q "$pattern" "$log" 2>/dev/null && return 0
    sleep 0.01
  done

  return 1
}

run_cleanup_case() {
  local name="$1" trigger="$2"
  local state="$test_tmp/$name" log="$test_tmp/$name.log" input="$test_tmp/$name.input"
  local input_fd status=0 cleanup_count pkill_count attempt

  mkdir -p "$state"
  mkfifo "$input"
  : >"$log"
  exec {input_fd}<>"$input"

  SCREENSAVER_TEST_STATE="$state" \
    SCREENSAVER_TEST_LOG="$log" \
    PATH="$stub_dir:$PATH" \
    bash "$ROOT/bin/omarchy-screensaver" <&"$input_fd" >"$state/output" 2>&1 &
  running_pid=$!

  wait_for_log '^ready$' "$log" || fail "$name starts the screensaver" "$(cat "$state/output")"

  if [[ $trigger == "signal" ]]; then
    kill -HUP "$running_pid"
  else
    printf 'x' >&"$input_fd"
  fi

  for attempt in {1..200}; do
    kill -0 "$running_pid" 2>/dev/null || break
    sleep 0.01
  done

  if kill -0 "$running_pid" 2>/dev/null; then
    fail "$name exits after cleanup" "$(cat "$state/output")"
  fi

  wait "$running_pid" || status=$?
  running_pid=
  exec {input_fd}>&-

  (( status == 0 )) || fail "$name exits successfully" "status: $status\n$(cat "$state/output")"

  cleanup_count=$(grep -c '^cleanup$' "$log" || true)
  (( cleanup_count == 1 )) || fail "$name cannot re-enter cleanup" "$(cat "$log")"

  pkill_count=$(grep -c '^pkill ' "$log" || true)
  (( pkill_count == 2 )) || fail "$name completes both cleanup steps once" "$(cat "$log")"

  pass "$name disarms signal traps before terminal teardown"
}

run_cleanup_case "signal handler" signal
run_cleanup_case "keyboard input" input
