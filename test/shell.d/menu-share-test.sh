#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin" "$test_home"

cat >"$mock_bin/wl-paste" <<'SH'
#!/bin/bash
if [[ $1 == "--list-types" ]]; then
  printf '%b' "${WL_PASTE_TYPES:-}"
  exit 0
fi

if [[ $1 == "--type" && $2 == text ]]; then
  [[ -n ${WL_PASTE_TEXT:-} ]] || exit 1
  printf '%s' "$WL_PASTE_TEXT"
  exit 0
fi

if [[ $1 == "--type" ]]; then
  [[ -n ${WL_PASTE_IMAGE:-} ]] || exit 1
  printf '%s' "$WL_PASTE_IMAGE"
  exit 0
fi

exit 1
SH

cat >"$mock_bin/systemd-run" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_SYSTEMD_RUN_LOG"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_NOTIFY_LOG"
SH

chmod +x "$mock_bin"/*

run_share_clipboard() {
  local systemd_run_log=$1 notify_log=$2
  shift 2

  status=0
  HOME="$test_home" PATH="$mock_bin:$PATH" \
    OMARCHY_TEST_SYSTEMD_RUN_LOG="$systemd_run_log" OMARCHY_TEST_NOTIFY_LOG="$notify_log" \
    "$@" bash "$ROOT/bin/omarchy-menu-share" clipboard || status=$?
}

# An image on the clipboard (e.g. a screenshot copied via `wl-copy --type
# image/png`) must reach LocalSend as the image, not as an empty text file.
systemd_run_log="$test_tmp/systemd-run.image"
notify_log="$test_tmp/notify.image"
: >"$systemd_run_log"
run_share_clipboard "$systemd_run_log" "$notify_log" \
  env WL_PASTE_TYPES='image/png\n' WL_PASTE_IMAGE=$'\x89PNGfakebytes'

((status == 0)) || fail "clipboard share exits 0 for an image clipboard"

sent_path=$(grep -oE '/[^ ]+\.png' "$systemd_run_log") || fail "clipboard share sends a .png file for an image clipboard" "$(cat "$systemd_run_log")"
[[ $(cat "$sent_path") == $'\x89PNGfakebytes' ]] || fail "clipboard share sends the actual image bytes, not an empty file"
pass "clipboard share sends the image when the clipboard holds image/png"

# Plain text clipboard content keeps working as a .txt file.
systemd_run_log="$test_tmp/systemd-run.text"
notify_log="$test_tmp/notify.text"
: >"$systemd_run_log"
run_share_clipboard "$systemd_run_log" "$notify_log" \
  env WL_PASTE_TYPES='text/plain\n' WL_PASTE_TEXT="hello clipboard"

((status == 0)) || fail "clipboard share exits 0 for a text clipboard"
sent_path=$(grep -oE '/[^ ]+\.txt' "$systemd_run_log") || fail "clipboard share sends a .txt file for a text clipboard" "$(cat "$systemd_run_log")"
[[ $(cat "$sent_path") == "hello clipboard" ]] || fail "clipboard share sends the actual text content"
pass "clipboard share still sends text clipboard content as .txt"

# An empty clipboard must not hand LocalSend a 0-byte file.
systemd_run_log="$test_tmp/systemd-run.empty"
notify_log="$test_tmp/notify.empty"
: >"$systemd_run_log"
: >"$notify_log"
run_share_clipboard "$systemd_run_log" "$notify_log" env WL_PASTE_TYPES='' WL_PASTE_TEXT=''

((status != 0)) || fail "clipboard share fails when the clipboard is empty"
[[ ! -s $systemd_run_log ]] || fail "clipboard share does not invoke LocalSend for an empty clipboard"
grep -qi "clipboard" "$notify_log" || fail "clipboard share notifies the user when the clipboard is empty" "$(cat "$notify_log")"
pass "clipboard share refuses to send an empty file for an empty clipboard"
