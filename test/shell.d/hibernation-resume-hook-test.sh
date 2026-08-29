#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

resume_config="$tmpdir/omarchy_resume.conf"
awk '
  /^  sudo tee .* <<'\''EOF'\''$/ { copying = 1; next }
  copying && /^EOF$/ { exit }
  copying { print }
' "$ROOT/bin/omarchy-hibernation-setup" >"$resume_config"

grep -qFx '# omarchy:resume-hook' "$resume_config" ||
  fail "hibernation setup emits the managed resume hook config"
pass "hibernation setup emits the managed resume hook config"

migration_config="$tmpdir/migrated_resume.conf"
awk '
  /^cat >"\$tmp" <<'\''EOF'\''$/ { copying = 1; next }
  copying && /^EOF$/ { exit }
  copying { print }
' "$ROOT/migrations/1787968459.sh" >"$migration_config"
cmp -s "$resume_config" "$migration_config" ||
  fail "the migration installs the same ordered resume hook config" "$(diff -u "$resume_config" "$migration_config")"
pass "the migration installs the same ordered resume hook config"

HOOKS=(base udev block encrypt filesystems fsck btrfs-overlayfs)
source "$resume_config"
[[ ${HOOKS[*]} == "base udev block encrypt resume filesystems fsck btrfs-overlayfs" ]] ||
  fail "resume is inserted before filesystems" "${HOOKS[*]}"
pass "resume is inserted before filesystems"

HOOKS=(base resume udev block encrypt filesystems fsck)
source "$resume_config"
[[ ${HOOKS[*]} == "base udev block encrypt resume filesystems fsck" ]] ||
  fail "an existing resume hook is repositioned without duplication" "${HOOKS[*]}"
pass "an existing resume hook is repositioned without duplication"

HOOKS=(base udev block encrypt)
source "$resume_config"
[[ ${HOOKS[*]} == "base udev block encrypt resume" ]] ||
  fail "resume is appended when filesystems is absent" "${HOOKS[*]}"
pass "resume is appended when filesystems is absent"

stub_bin="$tmpdir/bin"
migration_log="$tmpdir/migration.log"
rebuild_marker="$tmpdir/rebuild-complete"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
"$@"
SH

cat >"$stub_bin/limine-mkinitcpio" <<'SH'
#!/bin/bash
echo limine-mkinitcpio >>"$OMARCHY_TEST_MIGRATION_LOG"
[[ ${OMARCHY_TEST_REBUILD_FAIL:-false} != "true" ]]
SH

chmod +x "$stub_bin/sudo" "$stub_bin/limine-mkinitcpio"

run_migration() {
  PATH="$stub_bin:$PATH" \
    OMARCHY_RESUME_CONFIG="$resume_config" \
    OMARCHY_RESUME_REBUILD_MARKER="$rebuild_marker" \
    OMARCHY_TEST_MIGRATION_LOG="$migration_log" \
    OMARCHY_TEST_REBUILD_FAIL="${OMARCHY_TEST_REBUILD_FAIL:-false}" \
    bash -euo pipefail "$ROOT/migrations/1787968459.sh" >/dev/null
}

echo 'HOOKS+=(resume)' >"$resume_config"
if OMARCHY_TEST_REBUILD_FAIL=true run_migration; then
  fail "a failed resume-hook rebuild fails the migration"
fi
if ! grep -qFx '# omarchy:resume-hook' "$resume_config" || [[ -e $rebuild_marker ]]; then
  fail "a failed rebuild leaves the managed config retryable"
fi
pass "a failed resume-hook rebuild remains retryable"

run_migration
[[ -e $rebuild_marker ]] || fail "a successful rebuild records machine-wide completion"
(( $(grep -cFx limine-mkinitcpio "$migration_log") == 2 )) ||
  fail "the retry rebuilds after the first attempt fails" "$(cat "$migration_log")"
pass "a resume-hook rebuild retry records completion"

run_migration
(( $(grep -cFx limine-mkinitcpio "$migration_log") == 2 )) ||
  fail "another user skips the completed machine-wide rebuild" "$(cat "$migration_log")"
pass "a completed resume-hook rebuild is not repeated"
