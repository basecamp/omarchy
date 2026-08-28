#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
WATCHER_PID=""

cleanup() {
  if [[ -n $WATCHER_PID ]] && kill -0 "$WATCHER_PID" 2>/dev/null; then
    kill "$WATCHER_PID" 2>/dev/null || true
    wait "$WATCHER_PID" 2>/dev/null || true
  fi
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_command inotifywait

TMPDIR=$(mktemp -d)
plugins_dir="$TMPDIR/plugins"
linked_source="$TMPDIR/linked-source"
events="$TMPDIR/events"
mkdir -p "$plugins_dir" "$linked_source"
ln -s "$linked_source" "$plugins_dir/acme.linked"

"$ROOT/shell/scripts/watch-local-plugins" "$plugins_dir" >"$events" 2>&1 &
WATCHER_PID=$!
for _ in {1..30}; do
  printf 'updated %s\n' "$_" >"$linked_source/Overlay.qml"
  sleep 0.1
  grep -Fx -- "$plugins_dir/acme.linked/Overlay.qml" "$events" >/dev/null 2>&1 && break
done
grep -Fx -- "$plugins_dir/acme.linked/Overlay.qml" "$events" >/dev/null ||
  fail "linked plugin target writes reach the local plugin watcher"
pass "linked plugin target writes reach the local plugin watcher"

mkdir -p "$TMPDIR/replacement-source"
ln -s "$TMPDIR/replacement-source" "$plugins_dir/.acme.linked-replacement"
mv -T "$plugins_dir/.acme.linked-replacement" "$plugins_dir/acme.linked"

for _ in {1..30}; do
  grep -Fx -- "$plugins_dir/acme.linked" "$events" >/dev/null 2>&1 && break
  sleep 0.1
done
grep -Fx -- "$plugins_dir/acme.linked" "$events" >/dev/null ||
  fail "linked plugin replacement reaches the local plugin watcher"
pass "linked plugin replacement reaches the local plugin watcher"
