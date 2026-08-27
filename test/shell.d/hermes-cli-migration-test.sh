#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787760281.sh"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
hermes="$test_home/.local/bin/hermes"
marker="# Written by omarchy-install-hermes-cli."
mkdir -p "$mock_bin" "$test_home/.local/bin" "$test_home/.local/state/omarchy"

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_DESKTOP_INSTALLED:-0} == 1 ]]
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
! command -v "$1" >/dev/null 2>&1
SH

cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
[[ $1 != "where" ]]
SH

chmod +x "$mock_bin"/*

# The real installer is on PATH so the migration writes today's stub, not a
# copy of it.
run_migration() {
  OMARCHY_TEST_DESKTOP_INSTALLED="${1:-0}" \
    HOME="$test_home" \
    PATH="$mock_bin:$ROOT/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null 2>&1
}

run_migration || fail "the migration installs the wrapper on a plain install"
[[ -x $hermes ]] && grep -qxF "$marker" "$hermes" || fail "the migration writes the Omarchy wrapper"
pass "the migration installs the Hermes wrapper"

before=$(cat "$hermes")
run_migration || fail "rerunning the migration succeeds"
[[ $(cat "$hermes") == "$before" ]] || fail "rerunning the migration leaves the same wrapper"
pass "the migration is idempotent"

chmod -x "$hermes"
run_migration || fail "the migration repairs a non-executable Omarchy wrapper"
[[ -x $hermes ]] && grep -qxF "$marker" "$hermes" ||
  fail "the migration restores a non-executable Omarchy wrapper"
pass "the migration repairs a non-executable Omarchy wrapper"

rm -f "$hermes"
touch "$test_home/.local/state/omarchy/preinstalls-removed"
run_migration || fail "the migration succeeds for users who removed the preinstalls"
[[ ! -e $hermes ]] || fail "the migration respects the preinstalls opt-out"
pass "the migration skips users who removed the preinstalls"
rm -f "$test_home/.local/state/omarchy/preinstalls-removed"

run_migration 1 || fail "the migration succeeds when Hermes Desktop owns Hermes"
[[ ! -e $hermes ]] || fail "the migration writes nothing when Hermes Desktop owns Hermes"
pass "the migration stands aside for Hermes Desktop"

official_body="#!/bin/bash
unset PYTHONPATH
unset PYTHONHOME
exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\""
printf '%s\n' "$official_body" >"$hermes"
chmod +x "$hermes"
run_migration || fail "the migration succeeds over a foreign hermes command"
[[ $(cat "$hermes") == "$official_body" ]] || fail "the migration leaves a foreign hermes command alone"
pass "the migration preserves a foreign hermes command"

chmod -x "$hermes"
run_migration || fail "the migration succeeds over a non-executable foreign hermes"
[[ -f $hermes && ! -x $hermes && $(cat "$hermes") == "$official_body" ]] ||
  fail "the migration leaves a non-executable foreign hermes alone"
pass "the migration preserves a non-executable foreign hermes"

rm -f "$hermes"
ln -s "$test_home/nowhere/hermes" "$hermes"
run_migration || fail "the migration succeeds over a dangling hermes link"
[[ -L $hermes && $(readlink "$hermes") == "$test_home/nowhere/hermes" ]] ||
  fail "the migration leaves a dangling hermes link alone"
pass "the migration preserves a dangling hermes link"

rm -f "$hermes"
mkdir "$hermes"
run_migration || fail "the migration succeeds over a directory at the hermes path"
[[ -d $hermes ]] || fail "the migration leaves a directory at the hermes path alone"
pass "the migration preserves a directory at the hermes path"

rmdir "$hermes"
printf '%s\n' "#!/bin/bash" "# Replaces the stub omarchy-install-hermes-cli used to write." >"$hermes"
chmod +x "$hermes"
run_migration || fail "the migration succeeds over a wrapper that mentions the installer"
grep -qxF "$marker" "$hermes" && fail "the migration does not rewrite a wrapper that merely mentions the installer"
pass "the migration preserves a wrapper that merely mentions the installer"
