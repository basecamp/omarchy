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
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_compositor "menu select supersede test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping menu select supersede test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
scratch="$TMPDIR/scratch"
config_dir="$TMPDIR/menu-select-supersede"
mkdir -p "$config_dir" "$scratch"
cp "$SHELL_TEST_DIR/fixtures/menu-select-supersede/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Ui" "$config_dir/Ui"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
OMARCHY_MENU_TMP="$scratch" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$log" >&2
    fail "menu select supersede quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "menu select supersede test timed out"
}

fixture_failed=0
if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Menu select supersede result:\n' >&2
  jq . "$result" >&2
  fixture_failed=1
fi

for name in a b c d; do
  if [[ ! -e $scratch/done-$name ]]; then
    printf 'done-%s was never written; the displaced omarchy-menu-select waiter would spin forever\n' "$name" >&2
    fixture_failed=1
  fi
done

if (( fixture_failed )); then
  printf 'Quickshell log:\n' >&2
  sed -n '1,220p' "$log" >&2
  fail "superseding a pending menu select strands its waiter"
fi

pass "superseding a pending menu select finishes its request instead of leaking the waiter"
