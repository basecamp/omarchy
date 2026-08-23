#!/bin/bash

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
