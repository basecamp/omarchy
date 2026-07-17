#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub="$tmpdir/notify-send"
args_file="$tmpdir/args"

printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$@" >"$OMARCHY_TEST_NOTIFY_ARGS"' \
  >"$stub"
chmod +x "$stub"

OMARCHY_TEST_NOTIFY_ARGS="$args_file" PATH="$tmpdir:$ROOT/bin:$PATH" \
  omarchy-notification-send --app-name custom-app -g K -u critical --image /tmp/image.png "Learn Keybindings" "Body" -a

mapfile -t args <"$args_file"

[[ ${args[0]} == "-a" ]] || fail "notification wrapper passes app flag"
[[ ${args[1]} == "custom-app" ]] || fail "notification wrapper uses custom app name"
[[ ${args[2]} == "-u" ]] || fail "notification wrapper passes urgency flag"
[[ ${args[3]} == "critical" ]] || fail "notification wrapper uses custom urgency"
[[ ${args[4]} == "--hint=string:omarchy-glyph:K" ]] || fail "notification wrapper converts glyph to hint"
[[ ${args[5]} == "--hint=string:image-path:/tmp/image.png" ]] || fail "notification wrapper converts image to hint"
[[ ${args[6]} == "-A" ]] || fail "notification wrapper passes default action flag"
[[ ${args[7]} == "default=default" ]] || fail "notification wrapper enables default action"
[[ ${args[8]} == "Learn Keybindings" ]] || fail "notification wrapper preserves headline"
[[ ${args[9]} == "Body" ]] || fail "notification wrapper preserves description"
pass "notification wrapper supports app, glyph, urgency, image, and action options"
