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
reload_log="$TMPDIR/systemctl-calls"
cat >"$stub_bin/systemctl" <<STUB
#!/bin/bash
printf '%s\n' "\$*" >>"$reload_log"
STUB
chmod +x "$stub_bin/systemctl"

src="$TMPDIR/fprintd-resume"
printf '#!/bin/bash\n' >"$src"
chmod +x "$src"
dst="$TMPDIR/system-sleep/fprintd-resume"
dropin_src="$TMPDIR/10-stop-timeout.conf"
printf '[Service]\nTimeoutStopSec=3s\n' >"$dropin_src"
dropin_dst="$TMPDIR/fprintd.service.d/10-stop-timeout.conf"
lock_pam="$TMPDIR/omarchy-lock-fingerprint"

# omarchy-migrate runs each migration with `bash -euo pipefail`; match it.
run_migration() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_FPRINTD_RESUME_SRC="$src" \
    OMARCHY_FPRINTD_RESUME_DST="$dst" \
    OMARCHY_FPRINTD_STOP_TIMEOUT_SRC="$dropin_src" \
    OMARCHY_FPRINTD_STOP_TIMEOUT_DST="$dropin_dst" \
    OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
    bash -euo pipefail "$migration" >/dev/null ||
    fail "migration exits clean"
}

# The migration exits clean when its source is missing, so a hook moved
# without updating it would silently install nothing and mark itself done.
# Run once against the real default source under the repo to pin that path.
rm -rf "$TMPDIR/system-sleep" "$TMPDIR/fprintd.service.d"
: >"$lock_pam"
PATH="$stub_bin:$PATH" \
  OMARCHY_PATH="$ROOT" \
  OMARCHY_FPRINTD_RESUME_DST="$dst" \
  OMARCHY_FPRINTD_STOP_TIMEOUT_DST="$dropin_dst" \
  OMARCHY_LOCK_FINGERPRINT_PAM="$lock_pam" \
  bash -euo pipefail "$migration" >/dev/null ||
  fail "migration exits clean from its default sources"
[[ -x $dst ]] || fail "migration finds the hook at its default source path" "dst: $(stat -c '%A' "$dst" 2>/dev/null || echo missing)"
cmp -s "$dst" "$ROOT/default/systemd/system-sleep/fprintd-resume" || fail "migration installs the shipped hook from its default source"
cmp -s "$dropin_dst" "$ROOT/default/systemd/system/fprintd.service.d/10-stop-timeout.conf" || fail "migration installs the shipped drop-in from its default source"
pass "migration installs the shipped hook and drop-in from their default sources"

# A machine with fingerprint configured but no hook yet gets it, executable,
# plus the stop-timeout drop-in, and systemd is told about the drop-in.
: >"$lock_pam"
rm -rf "$TMPDIR/system-sleep" "$TMPDIR/fprintd.service.d"
: >"$reload_log"
run_migration
[[ -x $dst ]] || fail "migration installs the hook, executable" "dst: $(stat -c '%A' "$dst" 2>/dev/null || echo missing)"
pass "migration installs the hook, executable"
[[ $(stat -c '%a' "$dropin_dst" 2>/dev/null) == "644" ]] || fail "migration installs the stop-timeout drop-in" "dst: $(stat -c '%A' "$dropin_dst" 2>/dev/null || echo missing)"
grep -qx "daemon-reload" "$reload_log" || fail "migration reloads systemd after installing the drop-in" "calls: $(<"$reload_log")"
pass "migration installs the stop-timeout drop-in and reloads systemd"

# Running twice must not fail (both now exist), must not touch them, and has
# nothing to reload.
printf 'sentinel\n' >>"$dst"
printf '# sentinel\n' >>"$dropin_dst"
: >"$reload_log"
run_migration
grep -q sentinel "$dst" || fail "migration leaves an existing hook alone"
grep -q sentinel "$dropin_dst" || fail "migration leaves an existing drop-in alone"
[[ ! -s $reload_log ]] || fail "migration does not reload systemd when nothing changed" "calls: $(<"$reload_log")"
pass "migration leaves existing files alone"

# A copy under the old unprefixed name is replaced by the numbered one.
legacy="$TMPDIR/fprintd.service.d/stop-timeout.conf"
rm -f "$dropin_dst"; printf 'old\n' >"$legacy"
: >"$reload_log"
run_migration
[[ ! -e $legacy && -f $dropin_dst ]] || fail "migration replaces the unprefixed drop-in" "legacy: $(ls "$legacy" 2>&1); dst: $(ls "$dropin_dst" 2>&1)"
grep -qx "daemon-reload" "$reload_log" || fail "migration reloads systemd after replacing the drop-in"
pass "migration replaces the unprefixed drop-in with the numbered one"

# The drop-in is installed on its own where only the hook is already present.
rm -rf "$TMPDIR/fprintd.service.d"
run_migration
[[ -f $dropin_dst ]] || fail "migration adds the drop-in beside an existing hook"
pass "migration adds the drop-in beside an existing hook"

# No fingerprint configured -> nothing to fix, so nothing is installed.
rm -f "$lock_pam"
rm -rf "$TMPDIR/system-sleep" "$TMPDIR/fprintd.service.d"
run_migration
[[ ! -e $dst && ! -e $dropin_dst ]] || fail "migration skips machines without fingerprint configured"
pass "migration skips machines without fingerprint configured"
