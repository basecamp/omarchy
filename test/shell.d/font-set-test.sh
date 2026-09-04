#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
home="$tmpdir/home"
mkdir -p "$mock_bin" "$home/.config/ghostty" "$home/.config/foot"
printf 'font-family = "Old Font"\n' >"$home/.config/ghostty/config"
printf 'font=Old Font:size=9\n' >"$home/.config/foot/foot.ini"

cat >"$mock_bin/fc-list" <<'SH'
#!/bin/bash
printf 'Fira Mono:style=Regular\n'
SH

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
# procps-ng 4 pgrep has no -q short option. It always prints matching PIDs;
# callers quiet it with >/dev/null.
printf '15887\n'
exit 0
SH

cat >"$mock_bin/pkill" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-restart-shell" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$mock_bin/omarchy-hook" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"${OMARCHY_TEST_HOOK_LOG:?}"
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"${OMARCHY_TEST_NOTIFY_LOG:?}"
SH

chmod +x "$mock_bin"/*

hook_log="$tmpdir/hook.log"
notify_log="$tmpdir/notify.log"
: >"$hook_log"
: >"$notify_log"

output=$(
  HOME="$home" OMARCHY_TEST_HOOK_LOG="$hook_log" OMARCHY_TEST_NOTIFY_LOG="$notify_log" \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-font-set" "Fira Mono" 2>&1
) || fail "font set accepts a font name that contains a space" "$output"

[[ $output != *15887* ]] || fail "font set does not print pgrep PIDs" "$output"
[[ $output != *Usage:* ]] || fail "font set does not dump notification-send usage" "$output"
pass "font set stays quiet for a multi-word font name"

[[ -s $notify_log ]] || fail "font set notifies when Ghostty or Foot is running"
grep -Fq 'You must restart Ghostty to see font change' "$notify_log" ||
  fail "font set notifies Ghostty restart with the headline intact" "$(cat "$notify_log")"
grep -Fq 'You must restart Foot to see font change' "$notify_log" ||
  fail "font set notifies Foot restart with the headline intact" "$(cat "$notify_log")"
if grep -Eq '(^| )-g( |$)' "$notify_log"; then
  fail "font set does not pass a glyph flag" "$(cat "$notify_log")"
fi
pass "font set notification keeps the restart headline"

mapfile -d '' hook_args <"$hook_log"
[[ ${#hook_args[@]} == 2 && ${hook_args[0]} == "font-set" && ${hook_args[1]} == "Fira Mono" ]] ||
  fail "font set passes the full font name as one hook argument" "$(printf '%q ' "${hook_args[@]}")"
pass "font set passes the full font name as one hook argument"
