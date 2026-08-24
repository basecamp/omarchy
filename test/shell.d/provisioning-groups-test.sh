#!/bin/bash
#
# The install scripts that grant group memberships must record them in the provisioning
# groups file (for first-boot user creation and factory reset) and only call
# usermod when the install user actually exists.
#
# Docker is deliberately excluded: the docker group is root-equivalent, so it is
# no longer granted at install time (opt in with omarchy-setup-security-sudoless-docker).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export OMARCHY_PROVISIONING_DIR="$TMPDIR/provisioning"

# Stub getent/usermod: the fake system knows only the user "existing".
mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/getent" <<'STUB'
#!/bin/bash
[[ $1 == passwd && $2 == existing ]] && { echo "existing:x:1000:1000::/home/existing:/bin/bash"; exit 0; }
exit 2
STUB
cat >"$TMPDIR/bin/usermod" <<STUB
#!/bin/bash
echo "\$@" >>"$TMPDIR/usermod.calls"
STUB
chmod +x "$TMPDIR/bin/getent" "$TMPDIR/bin/usermod"
export PATH="$TMPDIR/bin:$PATH"

# No install user (deferred-provisioning install): input recorded, usermod not called.
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/config/docker.sh"
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/hardware/input-group.sh"

[[ -f $OMARCHY_PROVISIONING_DIR/groups ]] || fail "groups file written without an install user"
grep -qxF input "$OMARCHY_PROVISIONING_DIR/groups" || fail "input group recorded"
[[ ! -f $TMPDIR/usermod.calls ]] || fail "usermod not called without an install user"
pass "deferred provisioning records groups without calling usermod"

# The docker group is root-equivalent and must never be granted automatically.
! grep -qxF docker "$OMARCHY_PROVISIONING_DIR/groups" || fail "docker group must not be recorded"
pass "docker group is not recorded at install"

# Missing user (defensive): no usermod either.
OMARCHY_INSTALL_USER=ghost bash -eE "$ROOT/install/hardware/input-group.sh"
[[ ! -f $TMPDIR/usermod.calls ]] || fail "usermod not called for a missing user"
pass "missing install user defers group grants"

# Re-running never duplicates entries.
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/hardware/input-group.sh"
[[ $(grep -cxF input "$OMARCHY_PROVISIONING_DIR/groups") == 1 ]] || fail "input group recorded once"
pass "group recording is idempotent"

# Existing user: usermod applies the recorded groups, and docker is never among them.
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/config/docker.sh"
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/hardware/input-group.sh"
grep -qx -- "-aG input existing" "$TMPDIR/usermod.calls" || fail "usermod grants input to the install user"
! grep -q -- "docker" "$TMPDIR/usermod.calls" || fail "usermod must not grant docker to the install user"
pass "existing install user gets input but never docker"
