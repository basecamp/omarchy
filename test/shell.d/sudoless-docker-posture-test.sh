#!/bin/bash
#
# The docker group is root-equivalent, so no automatic path may grant it. These
# tests guard the paths that are not exercised by a fresh-install run: first-boot
# provisioning replaying a recorded (or factory-snapshot) group list, and the
# Quattro upgrade. Opting in stays a deliberate, warned step
# (omarchy-setup-security-sudoless-docker).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# First-boot provisioning must never grant docker even when it is recorded (an
# older install, or a factory snapshot predating the opt-in default).
mkdir -p "$TMPDIR/bin"
printf '#!/bin/bash\nexit 0\n' >"$TMPDIR/bin/getent" # every group "exists"
chmod +x "$TMPDIR/bin/getent"
export PATH="$TMPDIR/bin:$PATH"

PROVISIONING_DIR="$TMPDIR/prov"
mkdir -p "$PROVISIONING_DIR"
printf 'wheel\ninput\ndocker\n' >"$PROVISIONING_DIR/groups"

# Load the real user_groups() from the provisioning command and run it.
eval "$(sed -n '/^user_groups() {/,/^}/p' "$ROOT/bin/omarchy-provision-owner")"
groups=$(user_groups)

[[ ",$groups," == *",wheel,"* ]] || fail "user_groups always includes wheel"
[[ ",$groups," == *",input,"* ]] || fail "user_groups includes recorded non-docker groups"
[[ ",$groups," == *",docker,"* ]] && fail "user_groups must never grant the docker group"
pass "first-boot user_groups includes recorded groups but never docker"

# The Quattro upgrade must not re-add the user to docker.
if rg -q 'usermod -aG docker' "$ROOT/bin/omarchy-upgrade-to-quattro"; then
  fail "omarchy-upgrade-to-quattro must not add the user to the docker group"
fi
pass "the Quattro upgrade does not grant the docker group"
