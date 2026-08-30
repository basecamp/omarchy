#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
system_root="$test_tmp/system"
archive_root="$test_tmp/archive"
helper_copy="$test_tmp/omarchy-update-file-conflicts"
system_pkgs_copy="$test_tmp/omarchy-update-system-pkgs"
bootstrap_system_pkgs_copy="$test_tmp/omarchy-update-system-pkgs-bootstrap"
package_list="$test_tmp/package-files"
upgrade_list="$test_tmp/upgrade-packages"
cache_dirs="$test_tmp/cache-dirs"
owned_list="$test_tmp/owned-paths"
installed_owners="$test_tmp/installed-owners"
retry_installs="$test_tmp/retry-installs"
qlp_archives="$test_tmp/qlp-archives"
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

# Point a scratch copy of the public wrapper at the scratch root helper. The
# production wrapper deliberately uses the packaged /usr/bin helper and this
# checkout may be newer than the currently installed package.
sed \
  -e "s|/usr/bin/omarchy-update-file-conflicts|$helper_copy|g" \
  -e "s|/usr/bin/pacman|$stub_bin/pacman|g" \
  "$ROOT/bin/omarchy-update-system-pkgs" >"$system_pkgs_copy"
chmod +x "$system_pkgs_copy"

# Exercise the first rollout from a dev checkout, where this wrapper can be
# newer than the package that provides the fixed privileged helper.
sed \
  -e "s|/usr/bin/omarchy-update-file-conflicts|$test_tmp/missing-packaged-helper|g" \
  -e "s|/usr/bin/pacman|$stub_bin/pacman|g" \
  "$ROOT/bin/omarchy-update-system-pkgs" >"$bootstrap_system_pkgs_copy"
chmod +x "$bootstrap_system_pkgs_copy"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
if [[ ${1:-} == "$TEST_CONFLICT_HELPER" ]]; then
  shift
  exec env OMARCHY_TEST_ROOT_HELPER=1 "$TEST_CONFLICT_HELPER" "$@"
fi
if [[ ${1:-} == /usr/bin/env && ${2:-} == OMARCHY_UPDATE_PACMAN=1 && ${3:-} == "$TEST_PACMAN" ]]; then
  exec "$@"
fi
echo "unexpected sudo command: $*" >&2
exit 97
SH

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
set -euo pipefail

case ${1:-} in
-Qo)
  path=${@: -1}
  grep -Fxq -- "$path" "$OWNED_LIST"
  ;;
-Qoq)
  path=${@: -1}
  awk -F '\t' -v target="$path" '$1 == target { print $2; found = 1 } END { exit !found }' "$INSTALLED_OWNERS"
  ;;
-Sup)
  [[ $# == 6 && ${2:-} == --noconfirm && ${3:-} == --overwrite && \
    ${4:-} == '/usr/share/omarchy/*' && ${5:-} == --print-format && ${6:-} == $'%n\t%f' ]] || {
    echo "package plan does not match the authorizing transaction: $*" >&2
    exit 95
  }
  while IFS=$'\t' read -r package filename; do
    [[ -n $package && -n $filename ]] || continue
    printf '%s\t%s\n' "$package" "$filename"
  done <"$UPGRADE_LIST"
  ;;
-Qlp)
  archive=${@: -1}
  printf '%s\n' "$archive" >>"$QLP_ARCHIVES"
  filename=${archive##*/}
  while IFS=$'\t' read -r listed_filename listed_package path; do
    [[ $listed_filename == "$filename" ]] || continue
    printf '%s %s\n' "$listed_package" "$path"
  done <"$PACKAGE_LIST"
  [[ ${QLP_FAILS_AFTER_OUTPUT:-0} != 1 ]] || exit 1
  ;;
-Syu)
  [[ ${OMARCHY_TEST_ROOT_HELPER:-} == 1 || ${OMARCHY_TEST_BOOTSTRAP:-} == 1 ]] || {
    echo "package transaction escaped the root helper" >&2
    exit 98
  }
  attempt=$(($(<"$PACMAN_ATTEMPTS") + 1))
  printf '%s\n' "$attempt" >"$PACMAN_ATTEMPTS"
  printf '%s\n' "$1" >>"$PACMAN_OPERATIONS"
  [[ $# == 4 && ${2:-} == --noconfirm && ${3:-} == --overwrite && ${4:-} == '/usr/share/omarchy/*' ]] || {
    echo "initial package transaction options changed: $*" >&2
    exit 95
  }
  ((attempt == 1)) || {
    echo "file-conflict retry unexpectedly refreshed package databases" >&2
    exit 96
  }
  if [[ ${CLEAN_UPDATE:-0} != 1 ]]; then
    cat "$CONFLICT_REPORT" >&2
    exit "${PACMAN_FAILURE_STATUS:-1}"
  fi
  echo "upgrade complete"
  ;;
-Su)
  [[ ${OMARCHY_TEST_ROOT_HELPER:-} == 1 ]] || {
    echo "package retry escaped the root helper" >&2
    exit 98
  }
  attempt=$(($(<"$PACMAN_ATTEMPTS") + 1))
  printf '%s\n' "$attempt" >"$PACMAN_ATTEMPTS"
  printf '%s\n' "$1" >>"$PACMAN_OPERATIONS"
  [[ $# == 4 && ${2:-} == --noconfirm && ${3:-} == --overwrite && ${4:-} == '/usr/share/omarchy/*' ]] || {
    echo "package retry options changed: $*" >&2
    exit 95
  }
  ((attempt == 2)) || {
    echo "package retry did not follow the authorizing transaction" >&2
    exit 96
  }

  if [[ -n ${PIVOT_PARENT:-} ]]; then
    /usr/bin/mv -T -- "$PIVOT_PARENT" "$PIVOT_PARENT-original"
    /usr/bin/ln -s -- "$PIVOT_TARGET" "$PIVOT_PARENT"
  fi

  while IFS= read -r path; do
    [[ -n $path ]] || continue
    /usr/bin/mkdir -p -- "$(dirname -- "$path")"
    printf 'packaged\n' >"$path"
    package=$(awk -F '\t' -v target="$path" '$3 == target { print $2; exit }' "$PACKAGE_LIST")
    package=${RETRY_OWNER_OVERRIDE:-$package}
    [[ -n $package ]] || exit 94
    printf '%s\t%s\n' "$path" "$package" >>"$INSTALLED_OWNERS"
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

cat >"$stub_bin/flock" <<'SH'
#!/bin/bash
if [[ -n ${FLOCK_FAIL_STATUS:-} ]]; then
  exit "$FLOCK_FAIL_STATUS"
fi
exec /usr/bin/flock "$@"
SH

chmod +x "$stub_bin"/*

run_update() {
  TEST_CONFLICT_HELPER="$helper_copy" \
    TEST_PACMAN="$stub_bin/pacman" \
    OMARCHY_TEST_HELPER_PATH="$stub_bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/usr/sbin:/bin:/sbin" \
    PACKAGE_LIST="$package_list" UPGRADE_LIST="$upgrade_list" CACHE_DIRS="$cache_dirs" \
    OWNED_LIST="$owned_list" INSTALLED_OWNERS="$installed_owners" RETRY_INSTALLS="$retry_installs" \
    QLP_ARCHIVES="$qlp_archives" \
    PACMAN_ATTEMPTS="$test_tmp/attempts" CONFLICT_REPORT="$test_tmp/report" \
    PACMAN_OPERATIONS="$test_tmp/pacman-operations" \
    QLP_FAILS_AFTER_OUTPUT="${QLP_FAILS_AFTER_OUTPUT:-0}" \
    FLOCK_FAIL_STATUS="${FLOCK_FAIL_STATUS:-}" PACMAN_FAILURE_STATUS="${PACMAN_FAILURE_STATUS:-1}" \
    RETRY_OWNER_OVERRIDE="${RETRY_OWNER_OVERRIDE:-}" \
    RETRY_FAILS="${RETRY_FAILS:-0}" CLEAN_UPDATE="${CLEAN_UPDATE:-0}" \
    PIVOT_PARENT="${PIVOT_PARENT:-}" PIVOT_TARGET="${PIVOT_TARGET:-}" \
    FORWARD_ATTACK="${FORWARD_ATTACK:-0}" FORWARD_ATTACK_TARGET="${FORWARD_ATTACK_TARGET:-}" \
    FORWARD_ATTACK_MARK="$test_tmp/forward-attack-mark" \
    OMARCHY_TEST_BOOTSTRAP="${OMARCHY_TEST_BOOTSTRAP:-0}" \
    PATH="$stub_bin:$ROOT/bin:$PATH" bash "${UPDATE_SCRIPT:-$system_pkgs_copy}"
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
  : >"$installed_owners"
  : >"$retry_installs"
  : >"$qlp_archives"
  : >"$test_tmp/report"
  rm -f "$test_tmp/forward-attack-mark"
  printf '0\n' >"$test_tmp/attempts"
  : >"$test_tmp/pacman-operations"
}

make_file() {
  local path="$1" content="${2:-ours}"
  mkdir -p "$(dirname -- "$path")"
  chmod 0755 "$(dirname -- "$path")"
  printf '%s\n' "$content" >"$path"
}

cache_path() {
  local package="$1" path="$2" filename="${3:-$1.pkg.tar.zst}"
  printf '%s\t%s\t%s\n' "$filename" "$package" "$path" >>"$package_list"
  : >"$package_cache/$filename"
  chmod 0644 "$package_cache/$filename"
}

plan_package() {
  local package="$1" filename="${2:-$1.pkg.tar.zst}" record
  record="$package"$'\t'"$filename"
  grep -Fxq -- "$record" "$upgrade_list" || printf '%s\n' "$record" >>"$upgrade_list"
}

ship_path() {
  local package="$1" path="$2" filename="${3:-$1.pkg.tar.zst}"
  cache_path "$package" "$path" "$filename"
  plan_package "$package" "$filename"
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
[[ $(cat "$test_tmp/pacman-operations") == $'-Syu\n-Su' ]] || fail "file-conflict retry refreshes or changes the authorized transaction"
[[ -z $(find "$test_tmp" -maxdepth 1 -type d -name 'omarchy-update-pacman.*' -print -quit) ]] || fail "successful recovery leaves its root-only Pacman report behind"
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
custom_filename=omarchy-settings-dev.pkg.tar.zst
printf '%s\t%s\t%s\n' "$custom_filename" omarchy-settings-dev "$stray" >"$package_list"
plan_package omarchy-settings-dev "$custom_filename"
: >"$custom_cache/$custom_filename"
chmod 0644 "$custom_cache/$custom_filename"
printf '%s/\n' "$custom_cache" >"$cache_dirs"
printf '%s\n' "$stray" >"$retry_installs"
run_update >/dev/null 2>&1 ||
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

# A stale cached version of the right package is not authority for the pending
# version. Only the exact archive filename from Pacman's sysupgrade plan may
# contribute file-list entries.
reset_case
stray="$system_root/usr/lib/omarchy-test/stale-version.conf"
make_file "$stray"
write_report omarchy-settings-dev "$stray"
stale_filename=omarchy-settings-dev-1-old-any.pkg.tar.zst
pending_filename=omarchy-settings-dev-2-new-any.pkg.tar.zst
cache_path omarchy-settings-dev "$stray" "$stale_filename"
: >"$package_cache/$pending_filename"
chmod 0644 "$package_cache/$pending_filename"
plan_package omarchy-settings-dev "$pending_filename"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a stale archive for the pending package authorizes a root move"
fi
[[ -f $stray ]] || fail "a path absent from the exact pending archive was displaced"
[[ -z $(find_archived_content ours) ]] || fail "a stale package archive reached quarantine"
[[ $(<"$test_tmp/attempts") == 1 ]] || fail "archive mismatch reaches the package retry"
[[ $(<"$qlp_archives") == "$package_cache/$pending_filename" ]] || fail "archive authorization did not inspect the exact pending version"
pass "only the exact pending package archive authorizes cleanup"

# The exact-version check must select rather than blanket-reject when an older
# cache entry coexists with the pending archive.
reset_case
stray="$system_root/usr/lib/omarchy-test/pending-version.conf"
make_file "$stray"
write_report omarchy-settings-dev "$stray"
stale_filename=omarchy-settings-dev-1-old-any.pkg.tar.zst
pending_filename=omarchy-settings-dev-2-new-any.pkg.tar.zst
cache_path omarchy-settings-dev "$system_root/usr/lib/omarchy-test/stale-only.conf" "$stale_filename"
cache_path omarchy-settings-dev "$stray" "$pending_filename"
plan_package omarchy-settings-dev "$pending_filename"
printf '%s\n' "$stray" >"$retry_installs"
run_update >"$test_tmp/out" 2>"$test_tmp/err" ||
  fail "a valid pending archive is rejected when a stale version is also cached" "$(cat "$test_tmp/out" "$test_tmp/err")"
grep -qx packaged "$stray" || fail "the pending archive's conflict path was not installed"
[[ $(<"$qlp_archives") == "$package_cache/$pending_filename" ]] || fail "a stale cache entry was inspected instead of the pending archive"
pass "archive authorization selects the exact pending version among stale cache entries"

# Archive listing must complete successfully. Process-substitution status loss
# used to allow an early matching line from a damaged archive to pass.
reset_case
stray="$system_root/usr/lib/omarchy-test/damaged-archive.conf"
make_file "$stray"
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if QLP_FAILS_AFTER_OUTPUT=1 run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a partially readable package archive authorizes a root move"
fi
[[ -f $stray ]] || fail "a failed package archive listing displaced its path"
pass "package archive authorization fails closed on listing errors"

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
printf '%s\n' "$conflict_dir" >"$retry_installs"
run_update >/dev/null 2>&1 || fail "a verified conflicting directory is not cleared"
[[ -n $(find_archived_content inside) ]] || fail "a conflicting directory is not retained in quarantine"
pass "spaces and directories remain supported without mirrored destinations"

# A parent and descendant from one report could turn a moved, user-controlled
# directory into a traversal component for the later root move. Reject the
# complete report before staging either ordering.
for overlap_order in parent-first child-first; do
  reset_case
  overlap_parent="$system_root/usr/lib/omarchy-test/overlap"
  overlap_child="$overlap_parent/child.conf"
  make_file "$overlap_child" overlap
  if [[ $overlap_order == "parent-first" ]]; then
    write_raw_report \
      "omarchy-settings-dev: $overlap_parent exists in filesystem" \
      "omarchy-settings-dev: $overlap_child exists in filesystem"
  else
    write_raw_report \
      "omarchy-settings-dev: $overlap_child exists in filesystem" \
      "omarchy-settings-dev: $overlap_parent exists in filesystem"
  fi
  ship_path omarchy-settings-dev "$overlap_parent"
  ship_path omarchy-settings-dev "$overlap_child"
  if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
    fail "overlapping conflict paths are accepted in $overlap_order order"
  fi
  grep -Fq 'Refusing overlapping conflict paths' "$test_tmp/err" ||
    fail "overlapping conflicts do not fail at the overlap boundary"
  [[ -d $overlap_parent && -f $overlap_child ]] ||
    fail "overlap rejection moves an original object"
  [[ $(<"$test_tmp/attempts") == 1 ]] || fail "overlap rejection reaches the package retry"
  [[ -z $(find "$system_root" -type d -name '.omarchy-update-conflicts.*' -print -quit) ]] ||
    fail "overlap rejection creates a quarantine stage"
done
pass "parent and descendant conflicts are rejected before any root move"

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

# Pacman can return success after another process refreshes the sync databases
# and changes what -Su has left to install. Success is not enough: the conflict
# path must now exist and belong to the package that authorized its quarantine.
reset_case
stray="$system_root/usr/lib/omarchy-test/plan-drift.conf"
make_file "$stray" ours
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
if run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a successful retry that omits its conflict path reports success"
fi
grep -qx ours "$stray" || fail "a missing retry output does not restore the original"
[[ ! -d $archive_root ]] || fail "a fully restored plan drift leaves a quarantine archive"

reset_case
make_file "$stray" ours
write_report omarchy-settings-dev "$stray"
ship_path omarchy-settings-dev "$stray"
printf '%s\n' "$stray" >"$retry_installs"
if RETRY_OWNER_OVERRIDE=some-other-package run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a successful retry with the wrong package owner reports success"
fi
grep -qx packaged "$stray" || fail "postcondition failure overwrites retry output from another package"
[[ -n $(find_archived_content ours) ]] || fail "postcondition failure loses the displaced original"
pass "successful retries must install every quarantined path under the expected package"

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

# A direct unprivileged caller cannot invoke either privileged mutation path,
# while a clean update still runs exactly one pacman transaction. Keep this
# assertion unprivileged even when the suite itself was started by root: the
# production helper would otherwise run a real system upgrade.
root_helper_command=(bash "$ROOT/bin/omarchy-update-file-conflicts")
if ((EUID == 0)); then
  require_command setpriv
  root_helper_command=(setpriv --reuid=65534 --regid=65534 --clear-groups "${root_helper_command[@]}")
fi
if "${root_helper_command[@]}" </dev/null >/dev/null 2>&1; then
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

# Status 75 belongs only to the helper's explicit package-conflict handoff.
# util-linux commands can use the same sysexits value for an operational error;
# that must remain a normal failure rather than launching an interactive retry.
reset_case
if FLOCK_FAIL_STATUS=75 UPDATE_SCRIPT="$helper_copy" run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "an internal lock failure reports success"
else
  lock_failure_status=$?
fi
[[ $lock_failure_status == 1 ]] || fail "an internal status 75 escapes the reserved handoff boundary"
[[ $(<"$test_tmp/attempts") == 0 ]] || fail "a failed transaction lock reaches Pacman"
pass "only a genuine package conflict returns the interactive handoff status"

# The first dev-link rollout may execute this wrapper before the package has
# installed its fixed helper. It may bootstrap once through fixed system tools,
# but it must never parse/retry a conflict or use the checkout as root.
reset_case
if CLEAN_UPDATE=1 OMARCHY_TEST_BOOTSTRAP=1 UPDATE_SCRIPT="$bootstrap_system_pkgs_copy" \
  run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  bootstrap_status=0
else
  bootstrap_status=$?
fi
[[ $bootstrap_status == 0 ]] || fail "a clean missing-helper bootstrap fails"
[[ $(<"$test_tmp/attempts") == 1 && $(<"$test_tmp/pacman-operations") == -Syu ]] ||
  fail "the missing-helper bootstrap is not exactly one database-refreshing transaction"

reset_case
bootstrap_conflict="$system_root/etc/bootstrap.conf"
make_file "$bootstrap_conflict" bootstrap
write_report omarchy-settings-dev "$bootstrap_conflict"
if PACMAN_FAILURE_STATUS=42 OMARCHY_TEST_BOOTSTRAP=1 UPDATE_SCRIPT="$bootstrap_system_pkgs_copy" \
  run_update >"$test_tmp/out" 2>"$test_tmp/err"; then
  fail "a conflicting missing-helper bootstrap reports success"
else
  bootstrap_status=$?
fi
[[ $bootstrap_status == 42 ]] || fail "the bootstrap does not preserve Pacman's failure status"
grep -qx bootstrap "$bootstrap_conflict" || fail "the bootstrap conflict moved its original path"
[[ $(<"$test_tmp/attempts") == 1 && $(<"$test_tmp/pacman-operations") == -Syu ]] ||
  fail "the bootstrap conflict is parsed or retried"
[[ ! -d $archive_root ]] || fail "the bootstrap conflict creates a quarantine archive"
pass "a missing packaged helper bootstraps once and fails closed on conflicts"
