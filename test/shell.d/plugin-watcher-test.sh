#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""
STALE_PID=""
WATCHER_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill -KILL "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  for pid in "$STALE_PID" "$WATCHER_PID"; do
    if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

process_gone() {
  local pid=$1

  for _ in {1..50}; do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.1
  done

  return 1
}

require_compositor "plugin watcher test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping plugin watcher test"
  exit 0
fi

require_command inotifywait
require_command setpriv

TMPDIR=$(mktemp -d)
log="$TMPDIR/quickshell.log"
stale_log="$TMPDIR/stale.log"
config_dir="$TMPDIR/plugin-watcher"
plugins_dir="$TMPDIR/home/.config/omarchy/plugins"
mkdir -p "$config_dir" "$plugins_dir"
cp "$SHELL_TEST_DIR/fixtures/plugin-watcher/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/services" "$config_dir/services"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

# A watcher an earlier shell left behind, run with the shell's exact argv
# because that is all the shell reaps. Its cmdline reads inotifywait only once
# bash has exec'd it, which is when pkill can see it too.
inotifywait -m -r -q -e close_write,create,delete,move --format %w%f "$plugins_dir" >/dev/null 2>"$stale_log" &
STALE_PID=$!
for _ in {1..50}; do
  grep -qzxF -- inotifywait "/proc/$STALE_PID/cmdline" 2>/dev/null && break
  sleep 0.1
done
grep -qzxF -- inotifywait "/proc/$STALE_PID/cmdline" 2>/dev/null || fail "stale plugin watcher did not start" "$(<"$stale_log")"

OMARCHY_PATH="$ROOT" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..100}; do
  WATCHER_PID=$(pgrep -P "$QS_PID" -x inotifywait | head -n 1 || true)
  if [[ -n $WATCHER_PID ]] && grep -qzxF -- "$plugins_dir" "/proc/$WATCHER_PID/cmdline" 2>/dev/null; then
    break
  fi
  WATCHER_PID=""
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail "plugin watcher quickshell exited before starting its watcher" "$(sed -n '1,180p' "$log")"
  fi
  sleep 0.1
done

[[ -n $WATCHER_PID ]] || fail "plugin watcher did not start" "$(sed -n '1,180p' "$log")"

# The shell reaps stale watchers of its plugins dir before starting its own,
# so by now the one we planted must be gone, and gone from the shell's SIGTERM
# rather than from some failure of its own. Bash reaps a background child on
# SIGCHLD without a wait and keeps its status, so kill -0 stops seeing the
# watcher as soon as it dies while wait still reports how.
process_gone "$STALE_PID" || fail "stale plugin watcher survived shell start"
stale_status=0
wait "$STALE_PID" || stale_status=$?
STALE_PID=""
[[ $stale_status -eq 143 ]] || fail "stale plugin watcher did not die from the shell's SIGTERM" "exit status $stale_status: $(<"$stale_log")"

# A watcher that fails on its own moments after starting (an exhausted inotify
# quota, say) must not pass for one that died with the shell.
sleep 1
kill -0 "$WATCHER_PID" 2>/dev/null || fail "plugin watcher exited on its own" "$(sed -n '1,180p' "$log")"

# SIGKILL stands in for the shell leaving without any QML teardown, which is
# what happens when Qt aborts on a dropped Wayland connection.
kill -KILL "$QS_PID"
wait "$QS_PID" 2>/dev/null || true
QS_PID=""

process_gone "$WATCHER_PID" || fail "plugin watcher outlived the shell"
WATCHER_PID=""

pass "plugin registry reaps stale watchers and its watcher dies with the shell"
