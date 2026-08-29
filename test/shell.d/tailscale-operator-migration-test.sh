#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787884977.sh"
[[ -f $migration ]] || fail "Tailscale operator migration is missing"
pass "Tailscale operator migration exists"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
CALL_LOG="$tmp_dir/call-log"

cat >"$tmp_dir/bin/systemctl" <<'SH'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
exit 0
SH

cat >"$tmp_dir/bin/tailscale" <<'SH'
#!/bin/bash
printf 'tailscale %s\n' "$*" >>"$CALL_LOG"
if [[ $1 == "debug" && $2 == "prefs" ]]; then
  printf '{"OperatorUser":"%s"}\n' "${STUB_OPERATOR:-}"
  exit 0
fi
if [[ $1 == "set" ]]; then
  exit "${STUB_SET_STATUS:-0}"
fi
exit 0
SH

cat >"$tmp_dir/bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$tmp_dir/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "tailscale" ]]
SH

chmod +x "$tmp_dir/bin/systemctl" "$tmp_dir/bin/tailscale" "$tmp_dir/bin/sudo" "$tmp_dir/bin/omarchy-cmd-present"

: >"$CALL_LOG"

USER=omarchy-test \
PATH="$tmp_dir/bin:$PATH" \
CALL_LOG="$CALL_LOG" \
  bash -euo pipefail "$migration" >/dev/null

printf '%s\n' \
  "tailscale debug prefs" \
  "tailscale set --operator=omarchy-test" \
  "systemctl --user daemon-reload" \
  "systemctl --user enable --now omarchy-tailscale-receive.service" >"$tmp_dir/expected"
cmp -s "$CALL_LOG" "$tmp_dir/expected" ||
  fail "migration does not set the operator before enabling the Taildrop receiver" "$(cat "$CALL_LOG")"
pass "migration sets the operator before enabling the Taildrop receiver"

: >"$CALL_LOG"

cat >"$tmp_dir/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$tmp_dir/bin/omarchy-cmd-present"

PATH="$tmp_dir/bin:$PATH" \
CALL_LOG="$CALL_LOG" \
  bash -euo pipefail "$migration" >/dev/null

if [[ -s $CALL_LOG ]]; then
  fail "migration talks to Tailscale when it is not installed"
fi
pass "migration leaves Tailscale alone when it is not installed"

cat >"$tmp_dir/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "tailscale" ]]
SH
chmod +x "$tmp_dir/bin/omarchy-cmd-present"

: >"$CALL_LOG"

if USER=omarchy-test \
PATH="$tmp_dir/bin:$PATH" \
CALL_LOG="$CALL_LOG" \
STUB_SET_STATUS=1 \
  bash -euo pipefail "$migration" >/dev/null 2>&1; then
  fail "migration treats a failed operator set as success"
fi
if grep -q 'enable --now omarchy-tailscale-receive.service' "$CALL_LOG"; then
  fail "migration enables the receiver after a failed operator set"
fi
pass "migration stays pending when setting the operator fails"

: >"$CALL_LOG"

USER=omarchy-test \
PATH="$tmp_dir/bin:$PATH" \
CALL_LOG="$CALL_LOG" \
STUB_OPERATOR=other-user \
  bash -euo pipefail "$migration" >/dev/null

printf '%s\n' \
  "tailscale debug prefs" \
  "systemctl --user disable --now omarchy-tailscale-receive.service" >"$tmp_dir/expected"
cmp -s "$CALL_LOG" "$tmp_dir/expected" ||
  fail "migration does not disable a leftover receiver when the operator belongs to someone else" "$(cat "$CALL_LOG")"
pass "migration disables a leftover receiver when the operator belongs to someone else"
