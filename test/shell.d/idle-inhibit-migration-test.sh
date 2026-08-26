#!/bin/bash

# Packaging and rollout for the D-Bus inhibit daemon: the systemd user unit,
# the migration that enables it for existing installs (with the no-user-manager
# fallback the migrate-notify migration established), and the first-run list
# that starts it on fresh installs.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

unit="$ROOT/default/systemd/user/omarchy-idle-inhibit.service"
[[ -f $unit ]] || fail "the inhibit daemon ships a systemd user unit"

grep -Fx 'ExecStart=/usr/bin/omarchy-idle-inhibit-daemon' "$unit" >/dev/null ||
  fail "the unit starts the packaged daemon path"
grep -Fx 'After=graphical-session.target' "$unit" >/dev/null ||
  fail "the unit starts with the graphical session"
grep -Fx 'WantedBy=graphical-session.target' "$unit" >/dev/null ||
  fail "the unit is enabled with the graphical session"
grep -Fx 'Restart=always' "$unit" >/dev/null ||
  fail "the daemon restarts after a crash"
pass "the inhibit unit follows the house service pattern"

grep -q 'omarchy-idle-inhibit\.service' "$ROOT/install/user/first-run/enable-user-units.sh" ||
  fail "first-run starts the inhibit daemon on fresh installs"
pass "first-run starts the inhibit daemon on fresh installs"

# Anchor on the migration that mentions the daemon, not on filename order:
# another migration can land with a higher timestamp before this merges.
migration=$(grep -l 'omarchy-idle-inhibit' "$ROOT"/migrations/*.sh | head -n1)
[[ -n $migration ]] || fail "a migration enables the inhibit daemon"
[[ -x $migration ]] && fail "a migration is 0644, not executable"
head -n1 "$migration" | grep -q '^echo ' ||
  fail "a migration starts with an echo of what it does" "$(head -n1 "$migration")"
pass "the migration follows the house format rules"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
home="$test_tmp/home"
mkdir -p "$stub_bin" "$home"

# A live user manager: systemctl records what it was asked to do and succeeds.
cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
echo "systemctl $*" >>"${SYSTEMCTL_CALLS:?}"
exit 0
SH
chmod +x "$stub_bin/systemctl"

SYSTEMCTL_CALLS="$test_tmp/calls" \
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "the migration runs cleanly with a live user manager"

grep -q 'enable omarchy-idle-inhibit.service' "$test_tmp/calls" ||
  fail "the migration enables the inhibit unit" "$(cat "$test_tmp/calls")"
pass "the migration enables the inhibit unit"

# Idempotent: a second run is a no-op, not an error.
SYSTEMCTL_CALLS="$test_tmp/calls" \
  HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "the migration is idempotent"
pass "the migration is idempotent"

# `omarchy update` over SSH has no live user manager: systemctl fails, and the
# migration must write exactly the symlink enable would have written rather
# than silently doing nothing.
cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/systemctl"

HOME="$home" PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1 ||
  fail "the migration runs without a live user manager"

wants="$home/.config/systemd/user/graphical-session.target.wants/omarchy-idle-inhibit.service"
[[ -L $wants ]] || fail "the fallback writes the graphical-session wants symlink"
target=$(readlink "$wants")
[[ $target == "/usr/lib/systemd/user/omarchy-idle-inhibit.service" ]] ||
  fail "the fallback symlink points at the packaged unit" "$target"
pass "the fallback enables the unit without a user manager"
