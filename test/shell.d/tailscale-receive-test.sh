#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

WORKDIR=$(mktemp -d)
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

downloads="$WORKDIR/downloads"
mkdir -p "$WORKDIR/bin" "$downloads" "$WORKDIR/outbox"
printf 'mine' >"$downloads/unrelated.txt"

# Stands in for the daemon handing over whatever is waiting in the inbox. A
# decoy is whatever else drops into the downloads directory while Taildrop is
# still blocking on the next delivery.
cat >"$WORKDIR/bin/tailscale" <<SH
#!/bin/bash
target="\${*: -1}"
[[ -n \${DECOY:-} ]] && printf 'iso' >"$downloads/\$DECOY"
mv "$WORKDIR/outbox/"* "\$target/"
SH

cat >"$WORKDIR/bin/omarchy-notification-send" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$WORKDIR/notifications"
# Only the photo notification gets clicked.
[[ \$* == *photo.png* ]] && echo default
exit 0
SH

cat >"$WORKDIR/bin/xdg-open" <<SH
#!/bin/bash
printf '%s\n' "\$1" >>"$WORKDIR/opened"
SH

chmod +x "$WORKDIR/bin/"*

receive() {
  local expected="$1"
  shift

  : >"$WORKDIR/notifications"
  PATH="$WORKDIR/bin:$PATH" "$@" "$ROOT/bin/omarchy-tailscale-receive" --once "$downloads"

  for _ in {1..50}; do
    (($(wc -l <"$WORKDIR/notifications") >= expected)) && break
    sleep 0.1
  done
}

printf 'png' >"$WORKDIR/outbox/photo.png"
printf 'pdf' >"$WORKDIR/outbox/notes with space.pdf"
receive 2 env

notifications=$(<"$WORKDIR/notifications")

[[ -f $downloads/photo.png && -f "$downloads/notes with space.pdf" ]] ||
  fail "taildrop receive saves incoming files" "$(ls "$downloads")"
pass "taildrop receive saves incoming files"

grep -qF -- "Received photo.png Saved to $downloads --image $downloads/photo.png" <<<"$notifications" ||
  fail "taildrop receive previews received images" "$notifications"
pass "taildrop receive previews received images"

grep -q "^Received notes with space.pdf .* -g " <<<"$notifications" ||
  fail "taildrop receive announces other files with a glyph" "$notifications"
pass "taildrop receive announces other files with a glyph"

grep -qxF "$downloads/photo.png" "$WORKDIR/opened" ||
  fail "taildrop receive opens a clicked file" "$(cat "$WORKDIR/opened" 2>/dev/null)"
pass "taildrop receive opens a clicked file"

grep -q "unrelated.txt" <<<"$notifications" &&
  fail "taildrop receive leaves the rest of the downloads directory alone" "$notifications"
pass "taildrop receive leaves the rest of the downloads directory alone"

# A second delivery of the same name, alongside a download that arrives while
# Taildrop is waiting.
printf 'png' >"$WORKDIR/outbox/photo.png"
receive 1 env DECOY=browser-download.iso

notifications=$(<"$WORKDIR/notifications")

[[ -f $downloads/photo-1.png ]] || fail "taildrop receive keeps both files on a name clash" "$(ls "$downloads")"
grep -q "^Received photo-1.png " <<<"$notifications" ||
  fail "taildrop receive keeps both files on a name clash" "$notifications"
pass "taildrop receive keeps both files on a name clash"

grep -q "browser-download.iso" <<<"$notifications" &&
  fail "taildrop receive ignores downloads that arrive while it waits" "$notifications"
pass "taildrop receive ignores downloads that arrive while it waits"

[[ -z $(ls -A "$downloads/.omarchy-taildrop") ]] ||
  fail "taildrop receive empties its staging directory" "$(ls -A "$downloads/.omarchy-taildrop")"
pass "taildrop receive empties its staging directory"
