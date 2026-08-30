#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

mkdir -p "$WORKDIR/bin"

# Stands in for the clipboard: --list-types reports what is on offer, and a
# paste request records the negotiated type before handing the contents over.
cat >"$WORKDIR/bin/wl-paste" <<SH
#!/bin/bash
if [[ \$1 == "--list-types" ]]; then
  cat "$WORKDIR/types"
  exit 0
fi
printf '%s\n' "\${*: -1}" >>"$WORKDIR/paste-types"
if [[ -n \${WL_PASTE_FAIL:-} ]]; then
  echo "No suitable type of content copied" >&2
  exit 1
fi
cat "$WORKDIR/content"
SH

cat >"$WORKDIR/bin/tailscale" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$WORKDIR/tailscale-args"
args=("\$@")
cp -- "\${args[-2]}" "$WORKDIR/sent-payload" 2>/dev/null || true
[[ -n \${TAILSCALE_SLOW:-} ]] && sleep 2.5
if [[ -n \${TAILSCALE_FAIL:-} ]]; then
  echo "peer offline" >&2
  exit 1
fi
exit 0
SH

cat >"$WORKDIR/bin/omarchy-tailscale-send" <<SH
#!/bin/bash
printf '%s\n' "\$@" >"$WORKDIR/send-args"
SH

cat >"$WORKDIR/bin/omarchy-notification-send" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$WORKDIR/notifications"
SH

chmod +x "$WORKDIR/bin/"*

send() {
  : >"$WORKDIR/notifications"
  : >"$WORKDIR/tailscale-args"
  : >"$WORKDIR/paste-types"
  : >"$WORKDIR/send-args"
  PATH="$WORKDIR/bin:$PATH" "$ROOT/bin/omarchy-tailscale-send-clipboard" "$@"
}

printf 'text/plain;charset=utf-8\n' >"$WORKDIR/types"
printf 'hello from omarchy' >"$WORKDIR/content"
send zed.tail32f559.ts.net

grep -qE '^file cp --update-interval=0 -- .*/clipboard-[0-9]{6}\.txt zed\.tail32f559\.ts\.net:$' "$WORKDIR/tailscale-args" ||
  fail "clipboard text goes over as a taildrop text file" "$(<"$WORKDIR/tailscale-args")"
pass "clipboard text goes over as a taildrop text file"

[[ $(<"$WORKDIR/sent-payload") == "hello from omarchy" ]] ||
  fail "the clipboard contents arrive unchanged" "$(<"$WORKDIR/sent-payload")"
pass "the clipboard contents arrive unchanged"

grep -qF -- "Sent to zed Clipboard text" "$WORKDIR/notifications" ||
  fail "the success toast names the machine by its short name" "$(<"$WORKDIR/notifications")"
pass "the success toast names the machine by its short name"

grep -qF -- "Sending to zed" "$WORKDIR/notifications" &&
  fail "a quick transfer sends no progress toast" "$(<"$WORKDIR/notifications")"
pass "a quick transfer sends no progress toast"

printf 'image/png\ntext/plain;charset=utf-8\n' >"$WORKDIR/types"
printf 'PNGDATA' >"$WORKDIR/content"
send zed

grep -qE 'clipboard-[0-9]{6}\.png' "$WORKDIR/tailscale-args" ||
  fail "a clipboard image goes over as an image file" "$(<"$WORKDIR/tailscale-args")"
pass "a clipboard image goes over as an image file"

grep -qF "image/png" "$WORKDIR/paste-types" ||
  fail "the image is pasted with its image type" "$(<"$WORKDIR/paste-types")"
pass "the image is pasted with its image type"

printf 'image/svg+xml\n' >"$WORKDIR/types"
printf '<svg/>' >"$WORKDIR/content"
send zed

grep -qE 'clipboard-[0-9]{6}\.svg ' "$WORKDIR/tailscale-args" ||
  fail "a structured image type gets a plain extension" "$(<"$WORKDIR/tailscale-args")"
pass "a structured image type gets a plain extension"

: >"$WORKDIR/types"
status=0
send zed || status=$?
((status == 1)) || fail "an empty clipboard refuses to send" "exit $status"
pass "an empty clipboard refuses to send"

grep -qF -- "-u critical Could not send to zed The clipboard is empty" "$WORKDIR/notifications" ||
  fail "an empty clipboard is announced" "$(<"$WORKDIR/notifications")"
pass "an empty clipboard is announced"

printf 'text/plain;charset=utf-8\n' >"$WORKDIR/types"
: >"$WORKDIR/content"
status=0
send zed || status=$?
((status == 1)) || fail "empty clipboard text refuses to send" "exit $status"
[[ ! -s $WORKDIR/tailscale-args ]] ||
  fail "empty clipboard text never reaches taildrop" "$(<"$WORKDIR/tailscale-args")"
pass "empty clipboard text refuses to send"

printf 'text/plain;charset=utf-8\nx-kde-passwordManagerHint\n' >"$WORKDIR/types"
printf 'hunter2' >"$WORKDIR/content"
status=0
send zed || status=$?
((status == 1)) || fail "a password manager copy refuses to send" "exit $status"
grep -qF -- "The clipboard holds a password" "$WORKDIR/notifications" ||
  fail "a password manager copy is refused by name" "$(<"$WORKDIR/notifications")"
[[ ! -s $WORKDIR/tailscale-args ]] ||
  fail "a password manager copy never reaches taildrop" "$(<"$WORKDIR/tailscale-args")"
pass "a password manager copy refuses to send"

printf 'text/plain;charset=utf-8\n' >"$WORKDIR/types"
printf 'hello' >"$WORKDIR/content"
status=0
WL_PASTE_FAIL=1 send zed || status=$?
((status == 1)) || fail "a failed paste refuses to send" "exit $status"
grep -qF -- "Could not send to zed No suitable type of content copied" "$WORKDIR/notifications" ||
  fail "a failed paste surfaces the paste error" "$(<"$WORKDIR/notifications")"
[[ ! -s $WORKDIR/tailscale-args ]] ||
  fail "a failed paste never reaches taildrop" "$(<"$WORKDIR/tailscale-args")"
pass "a failed paste refuses to send with the paste error"

mkdir -p "$WORKDIR/copied dir"
printf 'a' >"$WORKDIR/copied dir/photo one.jpg"
printf 'b' >"$WORKDIR/copied dir/notes.pdf"
printf 'text/uri-list\ntext/plain;charset=utf-8\n' >"$WORKDIR/types"
printf 'file://%s\r\nfile://%s\r\n' \
  "$WORKDIR/copied dir/photo one.jpg" "$WORKDIR/copied dir/notes.pdf" |
  sed 's/ /%20/g' >"$WORKDIR/content"
send zed

expected=$(printf '%s\n' zed "$WORKDIR/copied dir/photo one.jpg" "$WORKDIR/copied dir/notes.pdf")
[[ $(<"$WORKDIR/send-args") == "$expected" ]] ||
  fail "copied files are handed to the file send as real paths" "$(<"$WORKDIR/send-args")"
[[ ! -s $WORKDIR/tailscale-args ]] ||
  fail "copied files do not also go over as text" "$(<"$WORKDIR/tailscale-args")"
pass "copied files are handed to the file send as real paths"

printf 'file:///nonexistent/gone.txt\n' >"$WORKDIR/content"
send zed
grep -qE 'clipboard-[0-9]{6}\.txt' "$WORKDIR/tailscale-args" ||
  fail "a stale uri list falls back to a text send" "$(<"$WORKDIR/tailscale-args")"
pass "a stale uri list falls back to a text send"

printf 'text/plain;charset=utf-8\n' >"$WORKDIR/types"
printf 'hello' >"$WORKDIR/content"
status=0
TAILSCALE_FAIL=1 send zed || status=$?
((status == 1)) || fail "a failed transfer reports failure" "exit $status"
pass "a failed transfer reports failure"

grep -qF -- "-u critical Could not send to zed peer offline" "$WORKDIR/notifications" ||
  fail "a failed transfer surfaces the taildrop error" "$(<"$WORKDIR/notifications")"
pass "a failed transfer surfaces the taildrop error"

TAILSCALE_SLOW=1 send zed
grep -qF -- "Sending to zed Clipboard text" "$WORKDIR/notifications" ||
  fail "a slow transfer announces itself in flight" "$(<"$WORKDIR/notifications")"
grep -qF -- "Sent to zed Clipboard text" "$WORKDIR/notifications" ||
  fail "a slow transfer still announces completion" "$(<"$WORKDIR/notifications")"
pass "a slow transfer announces itself in flight and on completion"
