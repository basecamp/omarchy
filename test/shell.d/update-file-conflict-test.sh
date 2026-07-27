#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

# Fails the first -Syu with the report under test, then succeeds unless the case
# asked for the retry to fail too.
cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
if [[ $1 == -Qo ]]; then
  # Anything in OWNED_PATHS has a package behind it; everything else is unowned.
  [[ " $OWNED_PATHS " == *" $2 "* ]]
  exit $?
fi

attempt=$(($(cat "$PACMAN_ATTEMPTS") + 1))
echo "$attempt" >"$PACMAN_ATTEMPTS"
if ((attempt == 1)); then
  cat "$CONFLICT_REPORT" >&2
  exit 1
fi
if [[ -n ${RETRY_FAILS:-} ]]; then
  # Optionally commit the file first, as a partial transaction would.
  [[ -n ${RETRY_INSTALLS:-} ]] && echo "packaged" >"$RETRY_INSTALLS"
  echo "error: failed to retrieve some files" >&2
  exit 1
fi
echo "upgrade complete"
STUB

chmod +x "$stub_bin/sudo" "$stub_bin/pacman"

replaced="$test_tmp/replaced"

run_update() {
  OMARCHY_REPLACED_DIR="$replaced" \
    RETRY_FAILS="${RETRY_FAILS:-}" \
    RETRY_INSTALLS="${RETRY_INSTALLS:-}" \
    PACMAN_ATTEMPTS="$test_tmp/attempts" \
    CONFLICT_REPORT="$test_tmp/report" \
    OWNED_PATHS="${OWNED_PATHS:-}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-update-system-pkgs"
}

# $1 blamed package, $2 path, $3 optional owning package.
write_report() {
  echo 0 >"$test_tmp/attempts"
  {
    echo "error: failed to commit transaction (conflicting files)"
    echo "$1: $2 exists in filesystem${3:+ (owned by $3)}"
  } >"$test_tmp/report"
}

# Raw conflict lines, for reports the recovery must refuse wholesale.
write_raw_report() {
  echo 0 >"$test_tmp/attempts"
  {
    echo "error: failed to commit transaction (conflicting files)"
    printf '%s\n' "$@"
  } >"$test_tmp/report"
}

work="$test_tmp/work"
fresh_work() {
  rm -rf "$work" "$replaced"
  mkdir -p "$work"
}

# An unowned path one of the packages is taking over.
fresh_work
stray="$work/omarchy-fcitx5.service"
echo "stray content" >"$stray"
write_report omarchy-settings-dev "$stray"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "an unowned file conflict is not resolved"
[[ ! -e $stray ]] ||
  fail "the file is left in pacman's way"
pass "a file pacman is taking over is moved out of its way"

# Kept out of the directory it came from, where SDDM and systemd-sleep read
# every file and every executable respectively.
[[ -z $(ls -A "$work") ]] ||
  fail "something is left in the directory the replaced file came from"
grep -qx "stray content" "$replaced$stray" ||
  fail "the replaced file is destroyed rather than kept out of the way"
pass "the replaced file is quarantined outside the directory it came from"

# A real fight between packages, not Omarchy's leftovers. pacman appends
# "(owned by ...)" here.
fresh_work
echo "theirs" >"$stray"
write_report omarchy-settings-dev "$stray" someone-else
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a file owned by another package is silently taken"
fi
[[ -e $stray && ! -e $replaced$stray ]] ||
  fail "a file owned by another package is silently taken"
pass "a conflict owned by another package stops the upgrade instead of being taken"

# Report reads unowned, database disagrees: the parse is never the only thing
# between a retry and another package's file.
fresh_work
echo "theirs" >"$stray"
write_report omarchy-settings-dev "$stray"
if OWNED_PATHS="$stray" run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "pacman -Qo is not consulted before moving a file"
fi
[[ -e $stray && ! -e $replaced$stray ]] ||
  fail "pacman -Qo is not consulted before moving a file"
pass "an owned path is left alone even when the report reads as unowned"

# A name prefix is not a namespace; only the packages that own system paths.
fresh_work
echo "stray" >"$stray"
write_report omarchy-chromium-bin "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "an optional omarchy-prefixed package gets its conflicts auto-resolved"
fi
pass "only the packages that own system paths get their conflicts resolved"

# Not Omarchy's conflict to resolve.
fresh_work
echo "stray" >"$stray"
write_report some-other-pkg "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a conflict from an unrelated package is auto-resolved"
fi
pass "a conflict from a non-Omarchy package is left for a human"

# The path is used literally, so glob characters in a name mean nothing.
fresh_work
globby="$work/omarchy-[1].conf"
echo "globby" >"$globby"
write_report omarchy-settings-dev "$globby"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a path whose name contains glob characters is not resolved"
[[ -f "$replaced$globby" && ! -e "$globby" ]] ||
  fail "a path whose name contains glob characters is treated as a pattern"
pass "a path whose name would act as a glob is moved literally"

# A leftover directory is cleared the same way a file is.
fresh_work
conflict_dir="$work/omarchy-dir"
mkdir -p "$conflict_dir"
write_report omarchy-settings-dev "$conflict_dir"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a conflicting directory is not cleared out of pacman's way"
[[ -d "$replaced$conflict_dir" && ! -e $conflict_dir ]] ||
  fail "a conflicting directory is left in place"
pass "a conflicting directory is moved away"

# A space is legal in a package path; the parse must not truncate it.
fresh_work
spaced="$work/omarchy theme.conf"
echo "spaced" >"$spaced"
write_report omarchy-settings-dev "$spaced"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a conflicting path containing a space is not resolved"
[[ -f "$replaced$spaced" && ! -e "$spaced" ]] ||
  fail "a conflicting path containing a space is truncated"
pass "a conflicting path containing a space is parsed whole"

# An earlier quarantined copy is the more original one, and might not be ours.
fresh_work
echo "current" >"$stray"
mkdir -p "$replaced$work"
echo "from an earlier run" >"$replaced$stray"
write_report omarchy-settings-dev "$stray"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a conflict with an existing quarantined copy is not resolved"
grep -qrx "from an earlier run" "$replaced" ||
  fail "an existing quarantined copy is destroyed to make room for a new one"
pass "an existing quarantined copy survives a later run needing the same name"

# mv without -T would move the source inside an existing destination directory.
fresh_work
echo "ours" >"$stray"
mkdir -p "$replaced$stray"
write_report omarchy-settings-dev "$stray"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a conflict whose destination is a directory is not resolved"
[[ -f "$replaced$stray" ]] ||
  fail "the leftover was moved inside the existing destination directory"
pass "an existing destination directory is replaced, not moved into"

# One healable conflict beside one that is not. Moving only the first leaves the
# retry blocked by the second, and that config inactive for nothing.
fresh_work
echo "ours" >"$stray"
write_raw_report \
  "omarchy-settings-dev: $stray exists in filesystem" \
  "some-package: $work/theirs exists in filesystem (owned by other-package)"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "an upgrade with an unhealable conflict reports success"
fi
[[ -e $stray && ! -e $replaced$stray ]] ||
  fail "a healable conflict is moved even though another conflict dooms the retry"
pass "nothing moves unless every reported conflict is healable"

# The retry can still fail for an unrelated reason. Leave nothing inactive.
fresh_work
echo "ours" >"$stray"
write_report omarchy-settings-dev "$stray"
if RETRY_FAILS=1 run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a failed retry reports success"
fi
[[ -f $stray ]] ||
  fail "a failed retry leaves the file moved away and inactive"
grep -qx "ours" "$stray" ||
  fail "the restored file is not the original content"
[[ $(cat "$test_tmp/attempts") == 2 ]] ||
  fail "the handler and the upgrade re-invoke each other instead of stopping"
pass "a failed retry puts the files back, without re-invoking the handler"

# A retry that failed after committing the files has nothing to restore, and
# should not announce a restore it is not doing.
fresh_work
echo "ours" >"$stray"
write_report omarchy-settings-dev "$stray"
if RETRY_FAILS=1 RETRY_INSTALLS="$stray" run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a failed retry reports success"
fi
grep -qi "restoring" "$test_tmp/out" "$test_tmp/err" &&
  fail "a restore is announced when no file is put back"
grep -qx "packaged" "$stray" ||
  fail "the file pacman installed was overwritten by the restore"
pass "no restore is announced when there is nothing to put back"

# A dangling symlink reads as absent to -e, so a relative link that no longer
# resolves from inside the quarantine must still be recognised and put back.
fresh_work
ln -s ./neighbour "$stray"
write_report omarchy-settings-dev "$stray"
if RETRY_FAILS=1 run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a failed retry reports success"
fi
[[ -L $stray ]] ||
  fail "a symlink that dangles from the quarantine is never restored"
pass "a dangling symlink is restored rather than stranded in the quarantine"

# The handler acts on a pacman report; an old or hand-written one would move
# live files aside for an upgrade that is not happening.
fresh_work
echo "ours" >"$stray"
write_report omarchy-settings-dev "$stray"
if PATH="$stub_bin:$ROOT/bin:$PATH" OMARCHY_REPLACED_DIR="$replaced" \
  bash "$ROOT/bin/omarchy-update-system-pkgs-when-conflicted" "$test_tmp/report" \
  >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "the handler acts on a report handed to it outside an update"
fi
[[ -f $stray ]] ||
  fail "the handler moved a live file when run outside an update"
pass "the handler refuses a report handed to it outside an update"

# The happy path must not pay for any of this.
fresh_work
: >"$test_tmp/report"
echo 1 >"$test_tmp/attempts"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a clean upgrade fails"
[[ $(cat "$test_tmp/attempts") == 2 ]] ||
  fail "a clean upgrade runs more than one pacman transaction"
pass "a clean upgrade runs a single pacman transaction"
