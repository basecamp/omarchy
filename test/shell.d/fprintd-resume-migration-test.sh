#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration=$(grep -rl 'Install the fingerprint resume hook on existing fingerprint setups' "$ROOT/migrations" | head -n 1 || true)
[[ -n $migration ]] || fail "fprintd resume hook migration exists"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# The migration installs to a system path via sudo; stub it so the test writes
# into a temp tree instead of /usr.
stub_bin="$TMPDIR/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$stub_bin/sudo"

src="$TMPDIR/fprintd-resume"
printf '#!/bin/bash\n' >"$src"
chmod +x "$src"
dst="$TMPDIR/system-sleep/fprintd-resume"
lock_pam="$TMPDIR/omarchy-lock-fingerprint"

# omarchy-migrate runs each migration with `bash -euo pipefail`; match it.
run_migration() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_FPRINTD_RESUME_SRC="$src" \
    OMARCHY_FPRINTD_RESUME_DST="$dst" \
    OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean"
}

# The migration exits clean when its source is missing, so a hook moved
# without updating it would silently install nothing and mark itself done.
# Run once against the real default source under the repo to pin that path.
rm -rf "$TMPDIR/system-sleep"
: >"$lock_pam"
PATH="$stub_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_FPRINTD_RESUME_DST="$dst" \
  OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "migration exits clean from its default source"
[[ -x $dst ]] || fail "migration finds the hook at its default source path" "dst: $(stat -c '%A' "$dst" 2>/dev/null || echo missing)"
cmp -s "$dst" "$ROOT/default/systemd/system-sleep/fprintd-resume" || fail "migration installs the shipped hook from its default source"
pass "migration installs the shipped hook from its default source"

# A machine with fingerprint configured but no hook yet gets it, executable.
: >"$lock_pam"
rm -rf "$TMPDIR/system-sleep"
run_migration
[[ -x $dst ]] || fail "migration installs the hook, executable" "dst: $(stat -c '%A' "$dst" 2>/dev/null || echo missing)"
pass "migration installs the hook, executable"

# Running twice must not fail (the hook now exists) and must not touch it.
printf 'sentinel\n' >>"$dst"
run_migration
grep -q sentinel "$dst" || fail "migration leaves an existing hook alone"
pass "migration leaves an existing hook alone"

# No fingerprint configured -> nothing to fix, so nothing is installed.
rm -f "$lock_pam"
rm -rf "$TMPDIR/system-sleep"
run_migration
[[ ! -e $dst ]] || fail "migration skips machines without fingerprint configured"
pass "migration skips machines without fingerprint configured"
