#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  # The plugin registry's watcher is a separate inotifywait that can outlive a
  # killed shell, and it inherits the runner's lock fd: leaving one behind wedges
  # every later shell test. The temp path makes the match ours alone.
  [[ -n $TMPDIR ]] && pkill -f "$TMPDIR" 2>/dev/null
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
  return 0
}
trap cleanup EXIT

require_compositor "shell config fallback test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping shell config fallback test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
log="$TMPDIR/quickshell.log"
user_config="$test_home/.config/omarchy/shell.json"
mkdir -p "$test_root" "$test_home/.config/omarchy"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
ln -s "$ROOT/bin" "$test_root/bin"

shell_ipc() {
  OMARCHY_PATH="$test_root" HOME="$test_home" "$ROOT/bin/omarchy-shell" "$@"
}

shell_ipc_quiet() {
  OMARCHY_PATH="$test_root" HOME="$test_home" "$ROOT/bin/omarchy-shell" -q "$@"
}

fail_with_log() {
  sed -n '1,240p' "$log" >&2
  fail "$1"
}

# A layout with no widgets in it: nothing here writes inline settings back to
# shell.json, so this script stays the only writer of the file under test.
write_user_config() {
  cat >"$user_config" <<JSON
{
  "version": 1,
  "bar": { "position": "$1", "transparent": true, "layout": { "left": [], "center": [], "right": [] } },
  "plugins": []
}
JSON
}

effective_position() {
  jq -r '.bar.position // "unset"' <<<"$(shell_ipc shell listShellConfig)"
}

alive() {
  kill -0 "$QS_PID" 2>/dev/null || fail_with_log "test shell exited while reloading shell.json"
}

reload_until() {
  shell_ipc_quiet shell reloadConfig >/dev/null
  local attempt
  for attempt in {1..40}; do
    [[ $(effective_position) == "$1" ]] && return 0
    alive
    sleep 0.1
  done
  return 1
}

# Asserting that a reload changed nothing needs a window rather than a sample:
# read until the reload has had time to land and fail the moment it moves, since
# a single early read would pass before the shell had even reparsed.
reload_holding() {
  shell_ipc_quiet shell reloadConfig >/dev/null
  local deadline=$((SECONDS + 3))
  while (( SECONDS < deadline )); do
    [[ $(effective_position) == "$1" ]] || return 1
    alive
    sleep 0.1
  done
  return 0
}

default_position=$(jq -r '.bar.position // "unset"' "$ROOT/config/omarchy/shell.json")

# Broken before the shell ever saw a good parse: there is no last good config to
# keep, so this has to land on the defaults rather than on nothing.
printf '{\n' >"$user_config"

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  shell_ipc_quiet shell ping >/dev/null 2>&1 && break
  kill -0 "$QS_PID" 2>/dev/null || fail_with_log "test shell exited before IPC became available"
  sleep 0.1
done

[[ $(effective_position) == "$default_position" ]] ||
  fail_with_log "unparseable shell.json with no last good config falls back to defaults (got $(effective_position))"
pass "unparseable shell.json with no last good config falls back to defaults"

write_user_config bottom
reload_until bottom || fail_with_log "valid shell.json applies (got $(effective_position))"
pass "valid shell.json applies"

# The point of the change: a half-written save keeps the layout the user last
# had rather than snapping the whole bar to defaults.
printf '{\n' >"$user_config"
reload_holding bottom ||
  fail_with_log "unparseable shell.json keeps the last good config (got $(effective_position))"
pass "unparseable shell.json keeps the last good config"

# ...and the other half: a user who deletes shell.json means it, so the
# remembered config must not outlive the file it came from.
rm -f "$user_config"
reload_until "$default_position" ||
  fail_with_log "deleting shell.json returns to defaults (got $(effective_position))"
pass "deleting shell.json returns to defaults"

printf '{\n' >"$user_config"
reload_holding "$default_position" ||
  fail_with_log "a broken save after a reset resurrects the deleted config (got $(effective_position))"
pass "a broken save after a reset does not resurrect the deleted config"
