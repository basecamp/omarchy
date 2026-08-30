#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1787691200.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_root="$test_tmp/root"
stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
transformed="$test_tmp/migration.sh"
legacy_path="$fake_root/usr/lib/chromium/initial_preferences"
mkdir -p "$stub_bin" "$test_home" "$(dirname "$legacy_path")"

sed "s#/usr/lib#$fake_root/usr/lib#g" "$migration" >"$transformed"

cat >"$stub_bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qo" ]] || exit 98
if [[ ${PACMAN_ERROR_PATH:-} == "$2" ]]; then
  echo "error: package database unavailable" >&2
  exit 2
elif [[ ${PREFS_OWNED:-} == 1 ]]; then
  echo "$2 is owned by chromium 1-1"
  exit 0
else
  echo "error: No package owns $2" >&2
  exit 1
fi
STUB

cat >"$stub_bin/sudo" <<'STUB'
#!/bin/bash
if [[ ${SUDO_FAIL:-0} == 1 ]]; then
  echo "sudo authentication failed" >&2
  exit 1
fi
exec "$@"
STUB

chmod +x "$stub_bin"/*

legacy_seed='{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}'
eula_seed='{"distribution":{"require_eula":false},"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}'

run_migration() {
  HOME="$test_home" \
    PACMAN_ERROR_PATH="${PACMAN_ERROR_PATH:-}" \
    PREFS_OWNED="${PREFS_OWNED:-}" \
    SUDO_FAIL="${SUDO_FAIL:-0}" \
    PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$transformed" >"$test_tmp/out" 2>"$test_tmp/err"
}

write_seed() {
  printf '%s\n' "$1" >"$legacy_path"
}

write_seed "$legacy_seed"
run_migration
[[ -f "$test_home/.config/chromium/EULA Accepted" ]] || fail "the Chromium EULA migration does not create per-user acceptance state"
[[ ! -e $legacy_path ]] || fail "the Chromium EULA migration does not retire the legacy 4.0 seed"
pass "Chromium EULA acceptance moves from unowned system state into the user profile"

write_seed "$eula_seed"
run_migration
[[ ! -e $legacy_path ]] || fail "the Chromium EULA migration does not retire the updated seed"
pass "the unreleased Chromium EULA seed is retired without becoming package debt"

write_seed '{"administrator":"changed this"}'
run_migration
grep -qx '{"administrator":"changed this"}' "$legacy_path" || fail "the Chromium EULA migration removes administrator state"
pass "the Chromium EULA migration preserves unknown local state"

write_seed "$legacy_seed"
PREFS_OWNED=1 run_migration
[[ -f $legacy_path ]] || fail "the Chromium EULA migration removes a package-owned file"
pass "the Chromium EULA migration never removes another package's file"

write_seed "$legacy_seed"
mv "$legacy_path" "$test_tmp/seed-target"
ln -s "$test_tmp/seed-target" "$legacy_path"
run_migration
[[ -L $legacy_path && -f $test_tmp/seed-target ]] || fail "the Chromium EULA migration follows a symlink"
pass "the Chromium EULA migration preserves linked administrator state"

rm -f "$legacy_path"
write_seed "$legacy_seed"
if PACMAN_ERROR_PATH="$legacy_path" run_migration; then
  fail "a package database error authorizes Chromium cleanup"
fi
[[ -f $legacy_path ]] || fail "a package database error removes Chromium state"
grep -q 'Unable to verify package ownership' "$test_tmp/err" || fail "a package database error is hidden"
pass "Chromium cleanup fails closed when Pacman cannot answer"

if SUDO_FAIL=1 run_migration; then
  fail "failed sudo authentication marks Chromium cleanup complete"
fi
[[ -f $legacy_path ]] || fail "a sudo failure removes Chromium state"
pass "Chromium cleanup remains retryable after a sudo failure"

[[ -f "$ROOT/config/chromium/EULA Accepted" ]] || fail "fresh users do not receive Chromium EULA acceptance from packaged defaults"
if rg -n '/usr/lib/chromium/initial_preferences' "$ROOT/bin" "$ROOT/install" >/dev/null; then
  fail "runtime or install code still writes Chromium's retired system seed"
fi
pass "fresh installs carry Chromium EULA acceptance only as packaged user defaults"
