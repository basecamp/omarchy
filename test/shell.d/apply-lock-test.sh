#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

apply_lock="$ROOT/bin/omarchy-apply-lock"

root_path_guard=$(awk '
  /^if \(\( EUID == 0 \)\); then$/ { inside = 1 }
  inside { print }
  inside && /^fi$/ { exit }
' "$apply_lock")
grep -Fx '  export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin' <<<"$root_path_guard" >/dev/null ||
  fail "the root lock helper replaces its inherited command path"
if grep -E '(\.local/bin|target_user|target_home)' <<<"$root_path_guard" >/dev/null; then
  fail "the root lock helper does not retain a user-controlled command directory"
fi
pass "the root lock helper uses only trusted command directories"

grep -F '[[ -x /usr/bin/fprintd-list ]]' "$apply_lock" >/dev/null ||
  fail "the lock helper checks the trusted fprintd-list executable"
grep -F '/usr/bin/fprintd-list "$target_user"' "$apply_lock" >/dev/null ||
  fail "the lock helper invokes fprintd-list by its trusted absolute path"
if grep -F 'omarchy-cmd-present fprintd-list' "$apply_lock" >/dev/null ||
  grep -E '(^|[[:space:];&|])fprintd-list([[:space:]]|$)' "$apply_lock" >/dev/null ||
  grep -E 'command[[:space:]]+-v[[:space:]]+fprintd-list' "$apply_lock" >/dev/null; then
  fail "the lock helper does not resolve fprintd-list through PATH"
fi
pass "the lock helper pins fprintd-list to its packaged system path"

# Exercise the helper as real root when the suite already has it, or as root in
# an unprivileged user namespace otherwise. A hardened kernel can disable user
# namespaces, so preserve the static coverage above and skip only this probe.
root_runner=()
root_runtime_available=1
if (( EUID != 0 )); then
  if command -v unshare >/dev/null && unshare --user --map-root-user true 2>/dev/null; then
    root_runner=(unshare --user --map-root-user)
  else
    root_runtime_available=0
  fi
fi

if (( ! root_runtime_available )); then
  pass "no unprivileged user namespace; skipping the root lock-helper lookup matrix"
  exit 0
fi

# Retarget the two PAM files, the trusted fprintd-list binary, and the final
# shell status query in copies under this scratch directory. The production
# files and service stay untouched even when this suite itself runs as root.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

poison_bin="$test_tmp/poison-bin"
trusted_root_bin="$test_tmp/trusted-root-bin"
trusted_fprintd="$test_tmp/trusted-fprintd-list"
password_pam="$test_tmp/omarchy-lock-password"
fingerprint_pam="$test_tmp/omarchy-lock-fingerprint"
attack_marker="$test_tmp/user-fprintd-list-ran"
trusted_uid="$test_tmp/trusted-fprintd-list.uid"
trusted_args="$test_tmp/trusted-fprintd-list.args"
attack_args="$test_tmp/user-fprintd-list.args"
patched_helper="$test_tmp/omarchy-apply-lock-patched"
absolute_only_helper="$test_tmp/omarchy-apply-lock-absolute-only"
root_path_only_helper="$test_tmp/omarchy-apply-lock-root-path-only"
unprotected_helper="$test_tmp/omarchy-apply-lock-unprotected"
target_user=omarchy-regression-user
mkdir -p "$poison_bin" "$trusted_root_bin"

# The runtime copy pins to this isolated root path. It contains every bare
# command the exercised helper needs, but deliberately no fprintd-list.
for helper in grep rm tee; do
  ln -s "/usr/bin/$helper" "$trusted_root_bin/$helper"
done

export TEST_ATTACK_ARGS="$attack_args"
export TEST_ATTACK_MARKER="$attack_marker"
export TEST_TRUSTED_ARGS="$trusted_args"
export TEST_TRUSTED_UID="$trusted_uid"

cat >"$trusted_fprintd" <<'EOF'
#!/bin/bash

printf '%s\n' "$EUID" >"$TEST_TRUSTED_UID"
printf '%s\n' "$*" >"$TEST_TRUSTED_ARGS"
echo "Fingerprints are enrolled"
EOF

cat >"$poison_bin/fprintd-list" <<'EOF'
#!/bin/bash

printf '%s\n' "$EUID" >"$TEST_ATTACK_MARKER"
printf '%s\n' "$*" >"$TEST_ATTACK_ARGS"
echo "Fingerprints are enrolled"
EOF

chmod +x "$trusted_fprintd" "$poison_bin/fprintd-list"

prepare_helper() {
  local destination="$1" keep_root_path="$2" use_absolute_fprintd="$3"

  awk \
    -v password_pam="$password_pam" \
    -v fingerprint_pam="$fingerprint_pam" \
    -v trusted_root_bin="$trusted_root_bin" \
    -v trusted_fprintd="$trusted_fprintd" \
    -v keep_root_path="$keep_root_path" \
    -v use_absolute_fprintd="$use_absolute_fprintd" '
    {
      line = $0
      gsub("/etc/pam\\.d/omarchy-lock-password", "\"" password_pam "\"", line)
      gsub("/etc/pam\\.d/omarchy-lock-fingerprint", "\"" fingerprint_pam "\"", line)

      if (line == "if (( EUID == 0 )); then" && keep_root_path == 0) {
        print "if (( 0 )); then"
        next
      }
      if (line == "  export PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin") {
        print "  export PATH=\"" trusted_root_bin "\""
        next
      }
      if (line == "if [[ -x /usr/bin/fprintd-list ]] &&") {
        if (use_absolute_fprintd == 1) {
          print "if [[ -x \"" trusted_fprintd "\" ]] &&"
        } else {
          print "if command -v fprintd-list >/dev/null 2>&1 &&"
        }
        next
      }
      if (line == "  /usr/bin/fprintd-list \"$target_user\" 2>/dev/null | grep -qi finger; then") {
        if (use_absolute_fprintd == 1) {
          print "  \"" trusted_fprintd "\" \"$target_user\" 2>/dev/null | grep -qi finger; then"
        } else {
          print "  fprintd-list \"$target_user\" 2>/dev/null | grep -qi finger; then"
        }
        next
      }
      if (line == "if omarchy-shell lock status >/dev/null 2>&1; then") {
        print "if false; then"
        next
      }

      print line
    }
  ' "$apply_lock" >"$destination"
  chmod +x "$destination"
}

prepare_helper "$patched_helper" 1 1
prepare_helper "$absolute_only_helper" 0 1
prepare_helper "$root_path_only_helper" 1 0
prepare_helper "$unprotected_helper" 0 0

for helper in "$patched_helper" "$absolute_only_helper" "$root_path_only_helper" "$unprotected_helper"; do
  if grep -F '/etc/pam.d/' "$helper" >/dev/null ||
    grep -F '/usr/bin/fprintd-list' "$helper" >/dev/null ||
    grep -F 'omarchy-shell lock status' "$helper" >/dev/null; then
    fail "the isolated root fixture redirects every live-system lock-helper target"
  fi
done

reset_runtime_files() {
  rm -f "$password_pam" "$fingerprint_pam" "$trusted_uid" "$trusted_args" "$attack_marker" "$attack_args"
}

run_as_root() {
  local helper="$1" description="$2" output

  if ! output=$(PATH="$poison_bin:/usr/bin:/bin" OMARCHY_INSTALL_USER="$target_user" \
    "${root_runner[@]}" /bin/bash "$helper" 2>&1); then
    fail "$description" "$output"
  fi
}

reset_runtime_files
run_as_root "$patched_helper" "the fully hardened lock helper runs in an isolated root context"
[[ ! -e $attack_marker ]] || fail "the hardened root lock helper executes the user-planted fprintd-list"
grep -Fx '0' "$trusted_uid" >/dev/null || fail "the trusted fprintd-list probe runs with EUID 0"
grep -Fx "$target_user" "$trusted_args" >/dev/null || fail "the trusted fprintd-list probe receives the target user"
[[ -s $password_pam && -s $fingerprint_pam ]] ||
  fail "the isolated root lock-helper run writes both scratch PAM fixtures"
pass "the hardened root lock helper uses the trusted fingerprint probe"

reset_runtime_files
run_as_root "$absolute_only_helper" "the absolute-path-only lock helper runs in an isolated root context"
[[ ! -e $attack_marker ]] || fail "an absolute fprintd-list path permits the user-planted command"
grep -Fx '0' "$trusted_uid" >/dev/null || fail "the absolute-path defense runs the trusted probe as root"
pass "the absolute fprintd-list path independently blocks the user-planted command"

reset_runtime_files
run_as_root "$root_path_only_helper" "the root-PATH-only lock helper runs in an isolated root context"
[[ ! -e $attack_marker ]] || fail "the trusted root path permits the user-planted fprintd-list"
pass "the trusted root path independently blocks the user-planted command"

# Mutation control: removing both protections must execute the planted command
# as UID 0, proving the matrix detects the original privilege-boundary failure.
reset_runtime_files
run_as_root "$unprotected_helper" "the unprotected mutation runs in an isolated root context"
grep -Fx '0' "$attack_marker" >/dev/null ||
  fail "the root lock-helper fixture detects a PATH-resolved fprintd-list regression"
grep -Fx "$target_user" "$attack_args" >/dev/null ||
  fail "the planted fprintd-list receives the target user"
[[ -s $fingerprint_pam ]] || fail "the planted fprintd-list controls the fingerprint PAM branch"
pass "the root lock-helper matrix rejects the vulnerable PATH lookup"
