#!/bin/bash

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
