#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
system_root="$test_tmp/system"
archive_root="$test_tmp/archive"
helper_copy="$test_tmp/omarchy-update-file-conflicts"
package_list="$test_tmp/package-files"
upgrade_list="$test_tmp/upgrade-packages"
cache_dirs="$test_tmp/cache-dirs"
owned_list="$test_tmp/owned-paths"
retry_installs="$test_tmp/retry-installs"
package_cache="$system_root/var/cache/pacman/pkg"
mkdir -p "$stub_bin"

# Retarget only a scratch copy of the root helper. Production contains no test
# path override and always uses /etc, /usr, and /var/lib/omarchy/replaced.
test_uid=$(id -u)
test_gid=$(id -g)
sed \
  -e 's/if ((EUID != 0)); then/if false; then/' \
  -e 's|export PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin|export PATH=${OMARCHY_TEST_HELPER_PATH:?}|' \
  -e 's/readonly ROOT_UID=0/readonly ROOT_UID='"$test_uid"'/' \
  -e 's/readonly ROOT_GID=0/readonly ROOT_GID='"$test_gid"'/' \
  -e "s|readonly ARCHIVE_BOUNDARY=/var|readonly ARCHIVE_BOUNDARY=$test_tmp|" \
  -e "s|readonly ARCHIVE_PARENT=/var/lib/omarchy|readonly ARCHIVE_PARENT=$test_tmp|" \
  -e "s|readonly ARCHIVE_ROOT=/var/lib/omarchy/replaced|readonly ARCHIVE_ROOT=$archive_root|" \
  -e "s|readonly PACKAGE_CACHE_BOUNDARY=/|readonly PACKAGE_CACHE_BOUNDARY=$system_root/var|" \
  -e "s|readonly REPORT_PARENT=/run|readonly REPORT_PARENT=$test_tmp|" \
  -e "s|allowed_roots=(/etc /usr)|allowed_roots=($system_root/etc $system_root/usr)|" \
  "$ROOT/bin/omarchy-update-file-conflicts" >"$helper_copy"
chmod +x "$helper_copy"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ ${1:-} == /usr/bin/omarchy-update-file-conflicts ]]; then
  shift
  exec env OMARCHY_TEST_ROOT_HELPER=1 "$TEST_CONFLICT_HELPER" "$@"
fi
exec "$@"
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Qo)
  path=${@: -1}
  grep -Fxq -- "$path" "$OWNED_LIST"
  ;;
-Sup)
  while IFS= read -r package; do
    [[ -n $package ]] || continue
    printf '%s\tfile://%s/%s.pkg.tar.zst\n' "$package" "$PACKAGE_CACHE" "$package"
  done <"$UPGRADE_LIST"
  ;;
-Qlp)
  while IFS=$'\t' read -r listed_package path; do
    printf '%s %s\n' "$listed_package" "$path"
  done <"$PACKAGE_LIST"
  ;;
-Syu)
  [[ ${OMARCHY_TEST_ROOT_HELPER:-} == 1 ]] || {
    echo "package transaction escaped the root helper" >&2
    exit 98
  }
  attempt=$(($(<"$PACMAN_ATTEMPTS") + 1))
  printf '%s\n' "$attempt" >"$PACMAN_ATTEMPTS"
  if ((attempt == 1)) && [[ ${CLEAN_UPDATE:-0} != 1 ]]; then
    cat "$CONFLICT_REPORT" >&2
    exit 1
  fi

  if [[ -n ${PIVOT_PARENT:-} ]]; then
    /usr/bin/mv -T -- "$PIVOT_PARENT" "$PIVOT_PARENT-original"
    /usr/bin/ln -s -- "$PIVOT_TARGET" "$PIVOT_PARENT"
  fi

  while IFS= read -r path; do
    [[ -n $path ]] || continue
    /usr/bin/mkdir -p -- "$(dirname -- "$path")"
    printf 'packaged\n' >"$path"
  done <"$RETRY_INSTALLS"

  if [[ ${RETRY_FAILS:-0} == 1 ]]; then
    echo "error: simulated retry failure" >&2
    exit 1
  fi
  echo "upgrade complete"
  ;;
*)
  echo "unexpected pacman invocation: $*" >&2
  exit 97
  ;;
esac
SH

cat >"$stub_bin/pacman-conf" <<'SH'
#!/bin/bash
[[ ${1:-} == CacheDir ]] || exit 97
cat "$CACHE_DIRS"
SH

# Deterministically insert a symlink into the first moved directory before the
# second forward move. A mirrored quarantine would let that link redirect the
# later root destination; opaque sibling slots must make it irrelevant.
cat >"$stub_bin/mv" <<'SH'
#!/bin/bash
/usr/bin/mv "$@"
status=$?
((status == 0)) || exit "$status"

destination=${@: -1}
if [[ ${FORWARD_ATTACK:-0} == 1 && $destination == */.omarchy-update-conflicts.*/item-0 && -d $destination && ! -e $FORWARD_ATTACK_MARK ]]; then
  /usr/bin/ln -s -- "$FORWARD_ATTACK_TARGET" "$destination/escape"
  : >"$FORWARD_ATTACK_MARK"
fi
SH

chmod +x "$stub_bin"/*

run_update() {
  TEST_CONFLICT_HELPER="$helper_copy" \
    OMARCHY_TEST_HELPER_PATH="$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin" \
    PACKAGE_LIST="$package_list" UPGRADE_LIST="$upgrade_list" CACHE_DIRS="$cache_dirs" \
    OWNED_LIST="$owned_list" RETRY_INSTALLS="$retry_installs" \
    PACKAGE_CACHE="${PACKAGE_CACHE_OVERRIDE:-$package_cache}" \
    PACMAN_ATTEMPTS="$test_tmp/attempts" CONFLICT_REPORT="$test_tmp/report" \
    RETRY_FAILS="${RETRY_FAILS:-0}" CLEAN_UPDATE="${CLEAN_UPDATE:-0}" \
    PIVOT_PARENT="${PIVOT_PARENT:-}" PIVOT_TARGET="${PIVOT_TARGET:-}" \
    FORWARD_ATTACK="${FORWARD_ATTACK:-0}" FORWARD_ATTACK_TARGET="${FORWARD_ATTACK_TARGET:-}" \
    FORWARD_ATTACK_MARK="$test_tmp/forward-attack-mark" \
    PATH="$stub_bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-update-system-pkgs"
}

reset_case() {
  rm -rf "$system_root" "$archive_root" "$package_cache"
  mkdir -p "$system_root/etc" "$system_root/usr" "$package_cache"
  chmod 0755 "$system_root/etc" "$system_root/usr" "$system_root/var" \
    "$system_root/var/cache" "$system_root/var/cache/pacman" "$package_cache"
  : >"$package_list"
  : >"$upgrade_list"
  printf '%s\n' "$package_cache" >"$cache_dirs"
  : >"$owned_list"
  : >"$retry_installs"
  : >"$test_tmp/report"
  rm -f "$test_tmp/forward-attack-mark"
  printf '0\n' >"$test_tmp/attempts"
}

make_file() {
  local path="$1" content="${2:-ours}"
  mkdir -p "$(dirname -- "$path")"
  chmod 0755 "$(dirname -- "$path")"
  printf '%s\n' "$content" >"$path"
}

cache_path() {
  printf '%s\t%s\n' "$1" "$2" >>"$package_list"
  : >"$package_cache/$1.pkg.tar.zst"
  chmod 0644 "$package_cache/$1.pkg.tar.zst"
}

plan_package() {
  grep -Fxq -- "$1" "$upgrade_list" || printf '%s\n' "$1" >>"$upgrade_list"
}

ship_path() {
  cache_path "$1" "$2"
  plan_package "$1"
}

write_report() {
  local package="$1" path="$2" owner="${3:-}"
  {
    echo "error: failed to commit transaction (conflicting files)"
    echo "$package: $path exists in filesystem${owner:+ (owned by $owner)}"
  } >"$test_tmp/report"
}

write_raw_report() {
  {
    echo "error: failed to commit transaction (conflicting files)"
    printf '%s\n' "$@"
  } >"$test_tmp/report"
}

find_archived_content() {
  local content="$1"
  grep -Rlx -- "$content" "$archive_root" 2>/dev/null | head -n1
}

# A legitimate unowned package target under a fixed system root is moved to an
# opaque slot, pacman installs its replacement, and the old bytes are retained.
reset_case
stray="$system_root/usr/lib/omarchy-test/legacy.conf"
make_file "$stray" "stray content"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
printf '%s\n' "$stray" >"$retry_installs"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a verified unowned file conflict is not resolved" "$(cat "$test_tmp/out" "$test_tmp/err")"
grep -qx packaged "$stray" || fail "pacman does not install the replacement after quarantine"
archived=$(find_archived_content "stray content")
[[ -n $archived && $(basename -- "$archived") == item-0 ]] || fail "replaced bytes are not stored under an opaque item name"
grep -RFq "$stray" "$archive_root"/transaction.*/ || fail "archive manifest records the original fixed path"
pass "verified file conflicts use an opaque root-owned quarantine"

# A failed archive-boundary check must stop before chmod(1), mktemp(1), or mv(1)
# can follow a planted archive symlink. cleanup() calls archive_remaining on the
# left of `||`, where Bash suppresses errexit inside the entire function.
reset_case
unsafe_archive_target="$test_tmp/unsafe-archive-target"
mkdir -p "$unsafe_archive_target"
chmod 0755 "$unsafe_archive_target"
ln -s "$unsafe_archive_target" "$archive_root"
stray="$system_root/usr/lib/omarchy-test/unsafe-archive.conf"
make_file "$stray" "unsafe archive payload"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
printf '%s\n' "$stray" >"$retry_installs"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "an unsafe archive symlink passes for completed conflict recovery"
fi
[[ -L $archive_root ]] || fail "the unsafe archive fixture no longer points at its target"
[[ $(stat -Lc '%a' "$unsafe_archive_target") == 755 ]] || fail "archive cleanup chmod follows an unsafe symlink"
[[ -z $(find "$unsafe_archive_target" -mindepth 1 -maxdepth 1 -name 'transaction.*' -print -quit) ]] ||
  fail "archive cleanup creates a transaction through an unsafe symlink"
retained=$(find "$system_root/usr" -type f -path '*/.omarchy-update-conflicts.*/item-*' -exec grep -lx 'unsafe archive payload' {} + 2>/dev/null | head -n1) || true
[[ -n $retained ]] || fail "an unsafe archive boundary loses the protected same-filesystem stage"
pass "unsafe archive boundaries retain staging without following symlinks"

# Text attribution is never enough: both package ownership and the package's
# sync file list are authoritative gates.
reset_case
stray="$system_root/usr/lib/omarchy-test/legacy.conf"
make_file "$stray"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
printf '%s\n' "$stray" >"$owned_list"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a package-owned path is moved"; fi
[[ -f $stray ]] || fail "a package-owned path does not remain in place"

: >"$owned_list"
: >"$package_list"
printf '0\n' >"$test_tmp/attempts"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a path absent from the package file list is moved"; fi
[[ -f $stray ]] || fail "an unverified path does not remain in place"

ship_path omarchy-settings-dev "$stray"
chmod 0777 "$package_cache"
printf '0\n' >"$test_tmp/attempts"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a package archive below a writable cache is trusted"; fi
[[ -f $stray ]] || fail "an untrusted package-cache path authorizes a move"
pass "live ownership and a trusted cached package archive both authorize cleanup"

# Pacman's configured cache directories, including non-default paths, are the
# source of the archive that will actually participate in the retry.
reset_case
custom_cache="$system_root/var/custom-pacman-cache"
mkdir -p "$custom_cache"
chmod 0755 "$custom_cache"
stray="$system_root/usr/lib/omarchy-test/custom-cache.conf"
make_file "$stray"
write_report omarchy-settings-dev "$stray"
printf '%s\t%s\n' omarchy-settings-dev "$stray" >"$package_list"
plan_package omarchy-settings-dev
: >"$custom_cache/omarchy-settings-dev.pkg.tar.zst"
chmod 0644 "$custom_cache/omarchy-settings-dev.pkg.tar.zst"
printf '%s/\n' "$custom_cache" >"$cache_dirs"
printf '%s\n' "$stray" >"$retry_installs"
PACKAGE_CACHE_OVERRIDE="$custom_cache" run_update >/dev/null 2>&1 ||
  fail "a trusted custom pacman cache is ignored"
grep -qx packaged "$stray" || fail "the custom-cache transaction does not install its conflict path"
pass "configured pacman cache directories authorize their pending archives"

# An explicitly named package is not necessarily part of `pacman -Syu`: it may
# be already current, ignored, or an inactive stable/dev variant. A cached
# archive alone must not authorize moving anything from the live system.
reset_case
stray="$system_root/usr/lib/omarchy-test/inactive.conf"
make_file "$stray"
write_report omarchy-settings-dev "$stray"
cache_path omarchy-settings-dev "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a cached package outside the sysupgrade transaction authorizes a move"; fi
[[ -f $stray ]] || fail "a non-transaction package displaced a live path"
pass "only packages in the pending sysupgrade transaction authorize cleanup"

# The caller's stdin used to become the privileged helper's authority through a
# user-owned temporary report. It is now irrelevant: only stderr captured by
# the helper's own root transaction can name paths to quarantine.
reset_case
real_conflict="$system_root/usr/lib/omarchy-test/real.conf"
injected_path="$system_root/usr/lib/omarchy-test/injected.conf"
make_file "$real_conflict" real
make_file "$injected_path" injected
write_report omarchy-settings-dev "$real_conflict"
ship_path omarchy-settings-dev "$real_conflict"
ship_path omarchy-settings-dev "$injected_path"
printf '%s\n' "$real_conflict" >"$retry_installs"
printf 'omarchy-settings-dev: %s exists in filesystem\n' "$injected_path" |
  run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a genuine conflict fails when the caller also supplies forged text"
grep -qx packaged "$real_conflict" || fail "the genuine root-captured conflict is not resolved"
grep -qx injected "$injected_path" || fail "caller-supplied conflict text authorizes a root move"
[[ -z $(find_archived_content injected) ]] || fail "caller-supplied text reaches the quarantine archive"
pass "only the privileged pacman attempt can authorize conflict quarantine"

# A forged report cannot name a home/tmp path, an unrelated package, or mix one
# healable line with one unsupported conflict.
reset_case
outside="$test_tmp/home/stage/payload"
make_file "$outside"
write_report omarchy-settings-dev "$outside"
ship_path omarchy-settings-dev "$outside"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a conflict outside fixed system roots is accepted"; fi
[[ -f $outside ]] || fail "an out-of-bound path was moved"

reset_case
stray="$system_root/etc/omarchy-test.conf"
make_file "$stray"
write_report some-other-package "$stray"
ship_path some-other-package "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "an unrelated package conflict is accepted"; fi
[[ -f $stray ]] || fail "an unrelated package path was moved"

reset_case
make_file "$stray"
write_raw_report \
  "omarchy-settings-dev: $stray exists in filesystem" \
  "some-package: $system_root/etc/theirs exists in filesystem (owned by other-package)"
ship_path omarchy-settings-dev "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a partially supported report is accepted"; fi
[[ -f $stray ]] || fail "anything moves before every conflict is validated"
pass "forged, unrelated, and partially supported reports cannot authorize root moves"

# Parent components must be real root-owned, non-writable directories.
reset_case
unsafe_parent="$system_root/usr/lib/writable-parent"
mkdir -p "$unsafe_parent"
chmod 0777 "$unsafe_parent"
stray="$unsafe_parent/legacy.conf"
printf 'ours\n' >"$stray"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a writable parent is trusted"; fi
[[ -f $stray ]] || fail "a path below a writable parent was moved"

reset_case
pivot_target="$test_tmp/pivot-target"
mkdir -p "$pivot_target"
mkdir -p "$system_root/usr/lib"
ln -s "$pivot_target" "$system_root/usr/lib/symlink-parent"
stray="$system_root/usr/lib/symlink-parent/legacy.conf"
printf 'ours\n' >"$pivot_target/legacy.conf"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a symlinked parent is trusted"; fi
[[ -f $pivot_target/legacy.conf ]] || fail "a path through a symlinked parent was moved"
pass "writable and symlinked parent chains are refused"

# Spaces are data, and a conflicting directory can be renamed without any root
# traversal through its attacker-controlled contents.
reset_case
spaced="$system_root/etc/omarchy theme.conf"
make_file "$spaced" spaced
write_report omarchy-settings-dev "$spaced"
ship_path omarchy-settings-dev "$spaced"
printf '%s\n' "$spaced" >"$retry_installs"
run_update >/dev/null 2>&1 || fail "a package path containing spaces is rejected"
grep -qx packaged "$spaced" || fail "a path containing spaces is truncated"

reset_case
conflict_dir="$system_root/usr/lib/omarchy-test/legacy-dir"
mkdir -p "$conflict_dir"
printf 'inside\n' >"$conflict_dir/file"
write_report omarchy-settings-dev "$conflict_dir"
ship_path omarchy-settings-dev "$conflict_dir"
run_update >/dev/null 2>&1 || fail "a verified conflicting directory is not cleared"
[[ -n $(find_archived_content inside) ]] || fail "a conflicting directory is not retained in quarantine"
pass "spaces and directories remain supported without mirrored destinations"

# On a failed retry, unchanged trusted parents allow an atomic same-filesystem
# restore. A partial pacman install is never overwritten by that rollback.
reset_case
stray="$system_root/usr/lib/omarchy-test/legacy.conf"
make_file "$stray" ours
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if RETRY_FAILS=1 run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a failed retry reports success"; fi
grep -qx ours "$stray" || fail "a failed retry does not restore the original file"
[[ ! -d $archive_root ]] || fail "a fully restored retry leaves a quarantine archive"
[[ $(<"$test_tmp/attempts") == 2 ]] || fail "the retry count is not bounded"

reset_case
make_file "$stray" ours
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
printf '%s\n' "$stray" >"$retry_installs"
if RETRY_FAILS=1 run_update >"$test_tmp/out" 2>"$test_tmp/err"; then fail "a failed partial retry reports success"; fi
grep -qx packaged "$stray" || fail "rollback overwrites a file pacman installed"
[[ -n $(find_archived_content ours) ]] || fail "the displaced original is lost after a partial retry"
pass "failed retries restore safely without overwriting package output"

# A dangling symlink is the moved object and is restored as a symlink.
reset_case
stray="$system_root/etc/omarchy-link"
ln -s ./missing-target "$stray"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if RETRY_FAILS=1 run_update >/dev/null 2>&1; then fail "a failed symlink retry reports success"; fi
[[ -L $stray && $(readlink "$stray") == ./missing-target ]] || fail "a dangling symlink is not restored literally"
pass "dangling symlinks are restored without being followed"

# Primary regression: swap the original parent for a symlink while pacman is
# retrying. The helper must revalidate the parent and archive the payload, never
# write through the replacement link.
reset_case
pivot_parent="$system_root/usr/lib/stage/escape"
mkdir -p "$pivot_parent"
stray="$pivot_parent/payload"
printf 'payload\n' >"$stray"
pivot_target="$test_tmp/fake-root"
mkdir -p "$pivot_target"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if RETRY_FAILS=1 PIVOT_PARENT="$pivot_parent" PIVOT_TARGET="$pivot_target" \
  run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "the deliberately failed pivot retry reports success"
fi
[[ -L $pivot_parent ]] || fail "the rollback test did not replace the original parent"
[[ ! -e $pivot_target/payload ]] || fail "rollback followed a replaced parent and escaped its trusted root"
[[ -n $(find_archived_content payload) ]] || fail "payload is lost when an unsafe restore is refused"
pass "rollback cannot follow a user-controlled parent symlink"

# Secondary regression: a symlink inserted inside the first moved directory
# cannot influence the destination of the next move because every item is a
# sibling under an opaque root-generated name.
reset_case
first="$system_root/usr/lib/omarchy-test/first-dir"
second="$system_root/usr/lib/omarchy-test/second.conf"
mkdir -p "$first"
printf 'first\n' >"$first/file"
make_file "$second" second
escape_target="$test_tmp/forward-escape"
mkdir -p "$escape_target"
write_raw_report \
  "omarchy-settings-dev: $first exists in filesystem" \
  "omarchy-settings-dev: $second exists in filesystem"
ship_path omarchy-settings-dev "$first"
ship_path omarchy-settings-dev "$second"
if FORWARD_ATTACK=1 FORWARD_ATTACK_TARGET="$escape_target" RETRY_FAILS=1 \
  run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "the deliberately failed forward-race retry reports success"
fi
[[ -f $test_tmp/forward-attack-mark ]] || fail "the forward-race fixture did not insert its symlink"
[[ ! -e $escape_target/second.conf && ! -e $escape_target/item-1 ]] ||
  fail "a symlink inside a moved directory redirected a later root move"
[[ -f $first/file && -f $second ]] || fail "failed forward-race retry does not restore both original objects"
pass "forward moves cannot traverse a symlink inside an earlier quarantined directory"

# A direct caller cannot invoke either privileged mutation path, while a clean
# update still runs exactly one pacman transaction.
if bash "$ROOT/bin/omarchy-update-file-conflicts" </dev/null >/dev/null 2>&1; then
  fail "unprivileged callers can invoke the root conflict helper"
fi
write_report omarchy-settings-dev "$system_root/etc/noop"
if PATH="$stub_bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-update-system-pkgs-when-conflicted" "$test_tmp/report" >/dev/null 2>&1; then
  fail "the interactive handler accepts a direct file-conflict report"
fi

reset_case
CLEAN_UPDATE=1 run_update >/dev/null 2>&1 || fail "a clean upgrade fails"
[[ $(<"$test_tmp/attempts") == 1 ]] || fail "a clean upgrade runs more than one pacman transaction"
pass "privileged conflict handling is internal and clean updates stay single-pass"
