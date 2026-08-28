#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787884977.sh"
[[ -f $migration ]] || fail "Tailscale operator migration is missing"
pass "Tailscale operator migration exists"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
TAILSCALE_LOG="$tmp_dir/tailscale-log"
SYSTEMCTL_LOG="$tmp_dir/systemctl-log"

cat >"$tmp_dir/bin/systemctl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
exit 0
SH

cat >"$tmp_dir/bin/tailscale" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TAILSCALE_LOG"
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

USER=omarchy-test \
PATH="$tmp_dir/bin:$PATH" \
TAILSCALE_LOG="$TAILSCALE_LOG" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
  bash -euo pipefail "$migration" >/dev/null

grep -Fqx -- "set --operator=omarchy-test" "$TAILSCALE_LOG" ||
  fail "migration does not set the Tailscale operator"
grep -Fqx -- "--user enable --now omarchy-tailscale-receive.service" "$SYSTEMCTL_LOG" ||
  fail "migration does not enable the Taildrop receiver after setting the operator"
pass "migration sets the operator before enabling the Taildrop receiver"

: >"$TAILSCALE_LOG"
: >"$SYSTEMCTL_LOG"

cat >"$tmp_dir/bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$tmp_dir/bin/omarchy-cmd-present"

PATH="$tmp_dir/bin:$PATH" \
TAILSCALE_LOG="$TAILSCALE_LOG" \
SYSTEMCTL_LOG="$SYSTEMCTL_LOG" \
  bash -euo pipefail "$migration" >/dev/null

if [[ -s $TAILSCALE_LOG || -s $SYSTEMCTL_LOG ]]; then
  fail "migration talks to Tailscale when it is not installed"
fi
pass "migration leaves Tailscale alone when it is not installed"
