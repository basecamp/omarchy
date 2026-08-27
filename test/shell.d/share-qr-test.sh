#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub="$tmpdir/bin"
mkdir -p "$stub"

cat >"$stub/qrencode" <<'SH'
#!/bin/bash
cat >"$QRENCODE_IN"
printf 'QR:%s\n' "$(<"$QRENCODE_IN")"
SH
cat >"$stub/wl-paste" <<'SH'
#!/bin/bash
# Only text/plain is a shareable clipboard payload for QR.
for arg in "$@"; do
  [[ $arg == text/plain ]] && printf '%s' "${PASTE:-}" && exit 0
done
exit 1
SH
cat >"$stub/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$NOTIFY_LOG"
SH
cat >"$stub/omarchy-launch-floating-terminal-with-presentation" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$LAUNCH_LOG"
env | grep -E '^OMARCHY_SHARE_QR_TEXT=' >"$LAUNCH_ENV" || true
SH
chmod +x "$stub"/*

run_qr() {
  PATH="$stub:$PATH" QRENCODE_IN="$tmpdir/qr-in" NOTIFY_LOG="$tmpdir/notify" LAUNCH_LOG="$tmpdir/launch" \
    LAUNCH_ENV="$tmpdir/launch-env" "$ROOT/bin/omarchy-share-qr" "$@"
}

: >"$tmpdir/notify"
if PATH="$stub:$PATH" PASTE="" NOTIFY_LOG="$tmpdir/notify" "$ROOT/bin/omarchy-share-qr" --display; then
  fail "share-qr refuses an empty clipboard"
fi
grep -Fq 'Nothing to share' "$tmpdir/notify" ||
  fail "share-qr names an empty clipboard" "$(cat "$tmpdir/notify")"
pass "share-qr refuses an empty clipboard"

output=$(PATH="$stub:$PATH" QRENCODE_IN="$tmpdir/qr-in" "$ROOT/bin/omarchy-share-qr" --display "https://omarchy.org")
[[ $output == "QR:https://omarchy.org" ]] ||
  fail "share-qr encodes an explicit argument" "$output"
[[ $(<"$tmpdir/qr-in") == "https://omarchy.org" ]] ||
  fail "share-qr hands the argument to qrencode" "$(cat "$tmpdir/qr-in")"
pass "share-qr encodes an explicit argument"

output=$(PATH="$stub:$PATH" QRENCODE_IN="$tmpdir/qr-in" "$ROOT/bin/omarchy-share-qr" --display hello world)
[[ $output == "QR:hello world" ]] ||
  fail "share-qr joins multi-word arguments" "$output"
pass "share-qr joins multi-word arguments"

output=$(PATH="$stub:$PATH" PASTE="hello from clip" QRENCODE_IN="$tmpdir/qr-in" "$ROOT/bin/omarchy-share-qr" --display)
[[ $output == "QR:hello from clip" ]] ||
  fail "share-qr encodes the clipboard" "$output"
pass "share-qr encodes the clipboard"

: >"$tmpdir/launch"
: >"$tmpdir/launch-env"
PATH="$stub:$PATH" PASTE="x" LAUNCH_LOG="$tmpdir/launch" LAUNCH_ENV="$tmpdir/launch-env" \
  "$ROOT/bin/omarchy-share-qr" </dev/null >/dev/null || true
[[ $(<"$tmpdir/launch") == "omarchy-share-qr --display" ]] ||
  fail "share-qr opens a floating terminal when stdout is not a tty" "$(cat "$tmpdir/launch")"
pass "share-qr opens a floating terminal when stdout is not a tty"

: >"$tmpdir/launch"
: >"$tmpdir/launch-env"
PATH="$stub:$PATH" LAUNCH_LOG="$tmpdir/launch" LAUNCH_ENV="$tmpdir/launch-env" \
  "$ROOT/bin/omarchy-share-qr" "https://omarchy.org/share" </dev/null >/dev/null || true
[[ $(<"$tmpdir/launch") == "omarchy-share-qr --display" ]] ||
  fail "share-qr reopens with --display for an explicit argument" "$(cat "$tmpdir/launch")"
grep -Fq 'OMARCHY_SHARE_QR_TEXT=https://omarchy.org/share' "$tmpdir/launch-env" ||
  fail "share-qr hands explicit text through the environment" "$(cat "$tmpdir/launch-env")"
pass "share-qr hands explicit text through the environment"

long=$(awk 'BEGIN { while (n++ < 2001) printf "a" }')
: >"$tmpdir/notify"
if PATH="$stub:$PATH" NOTIFY_LOG="$tmpdir/notify" "$ROOT/bin/omarchy-share-qr" --display "$long"; then
  fail "share-qr refuses a payload that cannot fit in a QR"
fi
grep -Fq 'Too much to encode' "$tmpdir/notify" ||
  fail "share-qr names an oversized payload" "$(cat "$tmpdir/notify")"
pass "share-qr refuses a payload that cannot fit in a QR"

grep -Fq '"trigger.share.qr"' "$ROOT/default/omarchy/omarchy-menu.jsonc" ||
  fail "share-qr is on the Share menu"
pass "share-qr is on the Share menu"
