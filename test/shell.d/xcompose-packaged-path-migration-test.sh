#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1787639388.sh"
[[ -f $migration ]] || fail "the XCompose packaged-path migration exists at $migration"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo\t%s\n' "$*" >>"$TEST_LOG"
"$@"
SH

cat >"$stub_bin/udevadm" <<'SH'
#!/bin/bash

printf 'udevadm\t%s\n' "$*" >>"$TEST_LOG"
SH

cat >"$stub_bin/omarchy-restart-xcompose" <<'SH'
#!/bin/bash

echo 'omarchy-restart-xcompose' >>"$TEST_LOG"
SH

chmod +x "$stub_bin"/*

packaged_include='include "/usr/share/omarchy/default/xcompose"'

reset_fixture() {
  rm -rf "$test_tmp/home" "$test_tmp/rules.d"
  mkdir -p "$test_tmp/home" "$test_tmp/rules.d"
  : >"$calls"
}

write_xcompose() {
  cat >"$test_tmp/home/.XCompose" <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
$1

# Identification
<Multi_key> <space> <n> : "Test User"
<Multi_key> <space> <e> : "test@example.com"
EOF
}

run_migration() {
  HOME="$test_tmp/home" \
    TEST_LOG="$calls" \
    OMARCHY_UDEV_RULES_DIR="$test_tmp/rules.d" \
    PATH="$stub_bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# Omarchy 3 wrote the include with the %H home shorthand; a hand-edited file may
# spell the same location with ~ or the expanded home. All of them only resolve
# through the ~/.local/share/omarchy compat symlink the upgrade left behind.
for legacy_include in \
  'include "%H/.local/share/omarchy/default/xcompose"' \
  'include "~/.local/share/omarchy/default/xcompose"' \
  "include \"$test_tmp/home/.local/share/omarchy/default/xcompose\""; do
  reset_fixture
  write_xcompose "$legacy_include"

  run_migration || fail "migration succeeds for $legacy_include"
  grep -qxF "$packaged_include" "$test_tmp/home/.XCompose" ||
    fail "migration points $legacy_include at the packaged compose file" "$(cat "$test_tmp/home/.XCompose")"
  ! grep -q 'local/share/omarchy' "$test_tmp/home/.XCompose" ||
    fail "migration leaves no legacy include behind for $legacy_include"
done
pass "migration repoints a legacy ~/.XCompose include at the packaged compose file"

grep -qF '<Multi_key> <space> <e> : "test@example.com"' "$test_tmp/home/.XCompose" ||
  fail "migration preserves the user's own compose sequences"
grep -qxF 'omarchy-restart-xcompose' "$calls" ||
  fail "migration reloads compose sequences after rewriting the include"
pass "migration keeps the user's sequences and reloads them"

reset_fixture
write_xcompose "$packaged_include"
before_hash=$(sha256sum "$test_tmp/home/.XCompose" | cut -d' ' -f1)
run_migration || fail "migration succeeds on an already packaged include"
[[ $(sha256sum "$test_tmp/home/.XCompose" | cut -d' ' -f1) == "$before_hash" ]] ||
  fail "migration leaves an already packaged include untouched"
! grep -q 'omarchy-restart-xcompose' "$calls" ||
  fail "migration does not restart compose when nothing changed"
pass "migration is idempotent on an already packaged include"

reset_fixture
run_migration || fail "migration succeeds without a ~/.XCompose"
[[ ! -e $test_tmp/home/.XCompose ]] || fail "migration does not create a ~/.XCompose"
pass "migration leaves a home without ~/.XCompose alone"

# Omarchy 3 installed these two rules with the user's checkout path baked in;
# quattro's shell switches power profiles itself, so the rules are dead weight
# that fails on every power-source change once the compat symlink is gone.
reset_fixture
cat >"$test_tmp/rules.d/99-power-profile.rules" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile /home/test/.local/share/omarchy/bin/omarchy-powerprofiles-set"
EOF
cat >"$test_tmp/rules.d/99-wifi-powersave.rules" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on /home/test/.local/share/omarchy/bin/omarchy-wifi-powersave on"
EOF
cat >"$test_tmp/rules.d/99-power-profile-custom.rules" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/local/bin/my-own-hook"
EOF
run_migration || fail "migration succeeds with legacy udev rules present"
[[ ! -e $test_tmp/rules.d/99-power-profile.rules ]] ||
  fail "migration removes the legacy power-profile udev rule"
[[ ! -e $test_tmp/rules.d/99-wifi-powersave.rules ]] ||
  fail "migration removes the legacy wifi-powersave udev rule"
[[ -e $test_tmp/rules.d/99-power-profile-custom.rules ]] ||
  fail "migration leaves unrelated udev rules alone"
grep -q '^sudo.*rm .*99-power-profile.rules' "$calls" ||
  fail "migration removes the rules through sudo"
grep -q '^udevadm.*control --reload' "$calls" ||
  fail "migration reloads udev after removing rules"
pass "migration removes the legacy power udev rules and reloads udev"

reset_fixture
cat >"$test_tmp/rules.d/99-power-profile.rules" <<'EOF'
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/local/bin/my-own-power-hook"
EOF
run_migration || fail "migration succeeds with a user-owned rule of the same name"
[[ -e $test_tmp/rules.d/99-power-profile.rules ]] ||
  fail "migration keeps a same-named rule that does not point at the legacy checkout"
! grep -q '^sudo' "$calls" || fail "migration does not touch sudo when nothing is removed"
pass "migration only removes rules that point at the legacy checkout"
