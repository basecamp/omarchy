#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""

cleanup() {
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_command jq

TMPDIR=$(mktemp -d)
test_home="$TMPDIR/home"
stub_bin="$TMPDIR/bin"
mkdir -p "$test_home" "$stub_bin"

# The capture itself needs a compositor, a picker and a clipboard, none of which
# a headless test run has. Stub the surface the command talks to so the file
# handling stays observable on its own.
cat >"$stub_bin/pkill" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$stub_bin/hyprctl" <<'SH'
#!/bin/bash
[[ $* == *"getoption cursor:no_hardware_cursors"* ]] && echo '{"int": 0}'
exit 0
SH

cat >"$stub_bin/omarchy-capture-region" <<'SH'
#!/bin/bash
# The command kills the freeze process it is handed, so hand it a real one.
sleep 30 &
echo "$!"
echo "0,0 100x100"
SH

cat >"$stub_bin/grim" <<'SH'
#!/bin/bash
target="${*: -1}"
if [[ $target == "-" ]]; then
  printf 'png-bytes'
else
  printf 'png-bytes' >"$target"
fi
SH

cat >"$stub_bin/wl-copy" <<'SH'
#!/bin/bash
cat >>"$STUB_LOG_DIR/wl-copy"
SH

cat >"$stub_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$STUB_LOG_DIR/notifications"
SH

chmod +x "$stub_bin"/*

# screenshot <case name> [VAR=value ...] [-- <command arguments>]
screenshot() {
  local case_dir="$TMPDIR/$1"
  shift

  local env_vars=()
  while (( $# )) && [[ $1 != "--" ]]; do
    env_vars+=("$1")
    shift
  done
  [[ ${1:-} == "--" ]] && shift

  local output_dir="$case_dir/pictures"
  local log_dir="$case_dir/log"
  mkdir -p "$log_dir"

  env -i \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    HOME="$test_home" \
    OMARCHY_PATH="$ROOT" \
    STUB_LOG_DIR="$log_dir" \
    OMARCHY_SCREENSHOT_DIR="$output_dir" \
    "${env_vars[@]}" \
    "$ROOT/bin/omarchy-capture-screenshot" "$@" >/dev/null
}

saved_count() {
  local dir="$1"

  if [[ -d $dir ]]; then
    find "$dir" -name 'screenshot-*.png' | wc -l
  else
    echo 0
  fi
}

screenshot default
(( $(saved_count "$TMPDIR/default/pictures") == 1 )) ||
  fail "the default flow writes a screenshot file"
pass "the default flow writes a screenshot file"

grep -q "saved to clipboard and file" "$TMPDIR/default/log/notifications" ||
  fail "the default flow reports the saved file" "$(cat "$TMPDIR/default/log/notifications")"
pass "the default flow reports the saved file"

screenshot clipboard-only OMARCHY_SCREENSHOT_SAVE_FILE=false
(( $(saved_count "$TMPDIR/clipboard-only/pictures") == 0 )) ||
  fail "OMARCHY_SCREENSHOT_SAVE_FILE=false writes no screenshot file"
pass "OMARCHY_SCREENSHOT_SAVE_FILE=false writes no screenshot file"

[[ ! -d $TMPDIR/clipboard-only/pictures ]] ||
  fail "OMARCHY_SCREENSHOT_SAVE_FILE=false leaves the screenshot directory uncreated"
pass "OMARCHY_SCREENSHOT_SAVE_FILE=false leaves the screenshot directory uncreated"

[[ -s $TMPDIR/clipboard-only/log/wl-copy ]] ||
  fail "OMARCHY_SCREENSHOT_SAVE_FILE=false still copies to the clipboard"
pass "OMARCHY_SCREENSHOT_SAVE_FILE=false still copies to the clipboard"

grep -q "Screenshot copied to clipboard" "$TMPDIR/clipboard-only/log/notifications" ||
  fail "the clipboard-only flow notifies without offering the editor" \
    "$(cat "$TMPDIR/clipboard-only/log/notifications")"
pass "the clipboard-only flow notifies without offering the editor"

screenshot explicit-save OMARCHY_SCREENSHOT_SAVE_FILE=false -- smart save
(( $(saved_count "$TMPDIR/explicit-save/pictures") == 1 )) ||
  fail "an explicit save argument writes a file even with saving turned off"
pass "an explicit save argument writes a file even with saving turned off"

screenshot unrecognized-value OMARCHY_SCREENSHOT_SAVE_FILE=nope
(( $(saved_count "$TMPDIR/unrecognized-value/pictures") == 1 )) ||
  fail "only an explicit false turns off saving"
pass "only an explicit false turns off saving"
