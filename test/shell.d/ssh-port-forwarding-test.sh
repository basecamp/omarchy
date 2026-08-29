#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

fns="$ROOT/default/bash/fns/ssh-port-forwarding"

# dip/lip must anchor on the ssh argv so an unanchored pkill -f cannot match a
# shell that merely mentions the -L fragment (#8917).
rg -q 'pkill -f "\^ssh \.\* -L \$\{port\}:localhost:\$\{port\}' "$fns" \
  || fail "dip anchors pkill on the ssh binary" "missing anchored pkill pattern"
pass "dip anchors pkill on the ssh binary"

rg -q 'pgrep -af "\^ssh \.\* -L \[0-9\]\+:localhost:\[0-9\]\+' "$fns" \
  || fail "lip anchors pgrep on the ssh binary" "missing anchored pgrep pattern"
pass "lip anchors pgrep on the ssh binary"

# A command line that only mentions the fragment (no leading ssh) must not match.
fragment='ssh.*-L 2222:localhost:2222'
anchored='^ssh .* -L 2222:localhost:2222( |$)'
printf '%s\n' "echo dip 2222 uses $fragment" | rg -q "$fragment" \
  || fail "legacy fragment still matches a shell cmdline" "expected a match"
pass "legacy fragment still matches a shell cmdline"
printf '%s\n' "echo dip 2222 uses -L 2222:localhost:2222" | rg -q "$anchored" \
  && fail "anchored pattern must not match a non-ssh cmdline" "unexpected match" \
  || pass "anchored pattern rejects a non-ssh cmdline"
printf '%s\n' "ssh -f -N -L 2222:localhost:2222 example.com" | rg -q "$anchored" \
  || fail "anchored pattern matches a real ssh forward" "expected a match"
pass "anchored pattern matches a real ssh forward"
