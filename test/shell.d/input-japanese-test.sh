#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
log="$work/calls"
: >"$log"

cat >"$work/bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_LOG"
SH

cat >"$work/bin/omarchy-restart-xcompose" <<'SH'
#!/bin/bash
printf 'restart-fcitx5\n' >>"$TEST_LOG"
SH

cat >"$work/bin/fcitx5-remote" <<'SH'
#!/bin/bash
case "$1" in
  --check) exit 0 ;;
  -q) printf 'Default\n' ;;
  *) exit 1 ;;
esac
SH

cat >"$work/bin/busctl" <<'SH'
#!/bin/bash
printf 'busctl' >>"$TEST_LOG"
printf ' <%s>' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"

case " $* " in
  *" InputMethodGroupInfo "*)
    if [[ ${MOZC_PRESENT:-false} == "true" ]]; then
      printf '%s\n' '{"type":"sa(ss)","data":["us",[["keyboard-us",""],["mozc",""]]]}'
    else
      printf '%s\n' '{"type":"sa(ss)","data":["us",[["keyboard-us",""],["keyboard-jp","jp"]]]}'
    fi
    ;;
esac
SH

chmod +x "$work/bin/omarchy-pkg-add" "$work/bin/omarchy-restart-xcompose" "$work/bin/fcitx5-remote" "$work/bin/busctl"

export TEST_LOG="$log"
export PATH="$work/bin:$PATH"

"$ROOT/bin/omarchy-setup-input-mozc" >"$work/output"

grep -Fx 'pkg-add fcitx5-mozc' "$log" >/dev/null ||
  fail "Japanese input installs the Mozc engine"
grep -Fx 'restart-fcitx5' "$log" >/dev/null ||
  fail "Japanese input restarts Fcitx so it discovers the newly installed engine"
grep -F '<SetInputMethodGroupInfo> <ssa(ss)> <Default> <us> <3> <keyboard-us> <> <keyboard-jp> <jp> <mozc> <>' "$log" >/dev/null ||
  fail "Japanese input preserves the current group and appends Mozc" "$(cat "$log")"
grep -F '<Save>' "$log" >/dev/null ||
  fail "Japanese input asks Fcitx to save the updated group"
grep -F 'Japanese input is ready' "$work/output" >/dev/null ||
  fail "Japanese input reports when setup is complete"
pass "Japanese input installs and registers Mozc"

: >"$log"
MOZC_PRESENT=true "$ROOT/bin/omarchy-setup-input-mozc" >"$work/output-existing"

grep -Fx 'pkg-add fcitx5-mozc' "$log" >/dev/null ||
  fail "Japanese input keeps package installation idempotent"
! grep -F '<SetInputMethodGroupInfo>' "$log" >/dev/null ||
  fail "Japanese input does not duplicate an existing Mozc entry" "$(cat "$log")"
grep -F 'Japanese input is ready' "$work/output-existing" >/dev/null ||
  fail "Japanese input reports an existing setup as ready"
pass "Japanese input setup is idempotent"
