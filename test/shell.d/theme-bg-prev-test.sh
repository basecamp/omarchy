#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub="$tmpdir/bin"
mkdir -p "$home/.local/state/omarchy/current/theme/backgrounds" "$stub"

printf 'tokyo-night\n' >"$home/.local/state/omarchy/current/theme.name"
for name in a-one.png b-two.png c-three.png; do
  printf 'img-%s' "$name" >"$home/.local/state/omarchy/current/theme/backgrounds/$name"
done

ln -s "$home/.local/state/omarchy/current/theme/backgrounds/b-two.png" \
  "$home/.local/state/omarchy/current/background"

cat >"$stub/omarchy-theme-bg-set" <<'SH'
#!/bin/bash
printf '%s\n' "$1" >"$BG_SET_LOG"
SH
cat >"$stub/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$NOTIFY_LOG"
SH
chmod +x "$stub/omarchy-theme-bg-set" "$stub/omarchy-notification-send"

HOME="$home" PATH="$stub:$PATH" BG_SET_LOG="$tmpdir/set" \
  "$BASH" "$ROOT/bin/omarchy-theme-bg-prev"

[[ $(<"$tmpdir/set") == "$home/.local/state/omarchy/current/theme/backgrounds/a-one.png" ]] ||
  fail "theme-bg-prev selects the previous background in sort order" "$(cat "$tmpdir/set")"
pass "theme-bg-prev selects the previous background"

ln -sfn "$home/.local/state/omarchy/current/theme/backgrounds/a-one.png" \
  "$home/.local/state/omarchy/current/background"

HOME="$home" PATH="$stub:$PATH" BG_SET_LOG="$tmpdir/set" \
  "$BASH" "$ROOT/bin/omarchy-theme-bg-prev"

[[ $(<"$tmpdir/set") == "$home/.local/state/omarchy/current/theme/backgrounds/c-three.png" ]] ||
  fail "theme-bg-prev wraps from the first background to the last" "$(cat "$tmpdir/set")"
pass "theme-bg-prev wraps around to the last background"

rm -f "$home/.local/state/omarchy/current/background"
HOME="$home" PATH="$stub:$PATH" BG_SET_LOG="$tmpdir/set" \
  "$BASH" "$ROOT/bin/omarchy-theme-bg-prev"

[[ $(<"$tmpdir/set") == "$home/.local/state/omarchy/current/theme/backgrounds/c-three.png" ]] ||
  fail "theme-bg-prev starts at the last background when none is current" "$(cat "$tmpdir/set")"
pass "theme-bg-prev starts at the last background when none is set"

rm -rf "$home/.local/state/omarchy/current/theme/backgrounds"
mkdir -p "$home/.local/state/omarchy/current/theme/backgrounds"
HOME="$home" PATH="$stub:$PATH" NOTIFY_LOG="$tmpdir/notify" \
  "$BASH" "$ROOT/bin/omarchy-theme-bg-prev"

grep -Fq 'No background was found for theme' "$tmpdir/notify" ||
  fail "theme-bg-prev notifies when the theme has no backgrounds" "$(cat "$tmpdir/notify")"
pass "theme-bg-prev notifies when there is nothing to cycle"
