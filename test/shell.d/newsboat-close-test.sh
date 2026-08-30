#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

export PATH="$mock_bin:$PATH"
export NEWSBOAT_CLOSE_TEST_LOG="$test_tmp/pkill"
export NEWSBOAT_CLOSE_TEST_STATE="$test_tmp/state"

write_mock() {
  local name=$1
  shift
  printf '#!/bin/bash\n%s\n' "$*" >"$mock_bin/$name"
  chmod +x "$mock_bin/$name"
}

write_mock pgrep '
count=0
[[ ! -f $NEWSBOAT_CLOSE_TEST_STATE ]] || count=$(<"$NEWSBOAT_CLOSE_TEST_STATE")
printf "%s\n" "$((count + 1))" >"$NEWSBOAT_CLOSE_TEST_STATE"
case ${NEWSBOAT_CLOSE_TEST_MODE:-none} in
  none) exit 1 ;;
  closes) (( count == 0 )) && exit 0 || exit 1 ;;
  stuck) exit 0 ;;
  error) exit 2 ;;
esac
'
write_mock pkill 'printf "%s\n" "$*" >>"$NEWSBOAT_CLOSE_TEST_LOG"'
write_mock sleep 'exit 0'

export NEWSBOAT_CLOSE_TEST_MODE=none
"$ROOT/bin/omarchy-newsboat-close"
[[ ! -e $NEWSBOAT_CLOSE_TEST_LOG ]] || fail "closing an absent Newsboat sends a signal"
pass "Newsboat close is a no-op without a running reader"

rm -f "$NEWSBOAT_CLOSE_TEST_STATE"
export NEWSBOAT_CLOSE_TEST_MODE=closes
"$ROOT/bin/omarchy-newsboat-close"
grep -Fxq -- "-TERM -u $UID -x newsboat" "$NEWSBOAT_CLOSE_TEST_LOG" || fail "Newsboat close does not target only this user's reader"
pass "Newsboat close waits for the reader to stop"

rm -f "$NEWSBOAT_CLOSE_TEST_STATE"
export NEWSBOAT_CLOSE_TEST_MODE=stuck NEWSBOAT_CLOSE_ATTEMPTS=2
if "$ROOT/bin/omarchy-newsboat-close" >/dev/null 2>&1; then
  fail "Newsboat close reports success while the reader remains"
fi
pass "Newsboat close fails safely when the reader remains"

rm -f "$NEWSBOAT_CLOSE_TEST_STATE"
export NEWSBOAT_CLOSE_TEST_MODE=error NEWSBOAT_CLOSE_ATTEMPTS=50
if "$ROOT/bin/omarchy-newsboat-close" >/dev/null 2>&1; then
  fail "Newsboat close ignores process inspection errors"
fi
pass "Newsboat close fails safely when process inspection is unavailable"
