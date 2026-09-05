#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/bin"

cat >"$tmpdir/bin/omarchy-launch-or-focus" <<'SH'
#!/bin/bash
eval "$2"
SH

cat >"$tmpdir/bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >"$CALLS"
SH

chmod +x "$tmpdir/bin/omarchy-launch-or-focus" "$tmpdir/bin/omarchy-launch-webapp"

marker="$tmpdir/not-run"
literal_flag="--user-agent=\$(touch $marker)"
CALLS="$tmpdir/calls" PATH="$tmpdir/bin:$PATH" "$ROOT/bin/omarchy-launch-or-focus-webapp" \
  "YouTube Music" "https://music.youtube.com" "--profile-directory=Profile 1" "$literal_flag"

mapfile -t calls <"$tmpdir/calls"
[[ ${calls[0]} == "https://music.youtube.com" ]] || fail "focused web app keeps its URL argument"
[[ ${calls[1]} == "--profile-directory=Profile 1" ]] || fail "focused web app keeps spaces in browser flags"
[[ ${calls[2]} == "$literal_flag" ]] || fail "focused web app keeps browser flags literal"
[[ ! -e $marker ]] || fail "focused web app does not execute browser flag contents"
pass "focused web apps preserve browser flag arguments"
