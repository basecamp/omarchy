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
cat >"$TMPDIR/bin/groupadd" <<STUB
#!/bin/bash
echo "\$@" >>"$TMPDIR/groupadd.calls"
STUB
cat >"$TMPDIR/bin/install" <<STUB
#!/bin/bash
echo "\$@" >>"$TMPDIR/install.calls"
STUB
cat >"$TMPDIR/bin/find" <<STUB
#!/bin/bash
echo "\$@" >>"$TMPDIR/find.calls"
STUB
cat >"$TMPDIR/bin/sudo" <<STUB
#!/bin/bash
echo "\$@" >>"$TMPDIR/sudo.calls"
exec "\$@"
STUB
chmod +x "$TMPDIR/bin"/{getent,usermod,groupadd,install,find,sudo}
export PATH="$TMPDIR/bin:$PATH"
export OMARCHY_PATH="$ROOT"

# No install user (deferred-provisioning install): groups recorded, usermod not called.
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/config/docker.sh"
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/hardware/input-group.sh"
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/config/browser-policy.sh"

[[ -f $OMARCHY_PROVISIONING_DIR/groups ]] || fail "groups file written without an install user"
grep -qxF input "$OMARCHY_PROVISIONING_DIR/groups" || fail "input group recorded"
! grep -qxF omarchy-browser-policy "$OMARCHY_PROVISIONING_DIR/groups" ||
  fail "browser-policy group must not be recorded"
[[ ! -f $TMPDIR/usermod.calls ]] || fail "usermod not called without an install user"
[[ ! -f $TMPDIR/groupadd.calls ]] || ! grep -F omarchy-browser-policy "$TMPDIR/groupadd.calls" >/dev/null ||
  fail "browser-policy group is not created"
grep -F -- '-d -m 0755 -o root -g root /etc/chromium/policies/managed' "$TMPDIR/install.calls" >/dev/null ||
  fail "browser-policy directory is created root-owned"
pass "deferred provisioning records groups without calling usermod"

# The docker group is root-equivalent and must never be granted automatically.
! grep -qxF docker "$OMARCHY_PROVISIONING_DIR/groups" || fail "docker group must not be recorded"
pass "docker group is not recorded at install"

# Missing user (defensive): no usermod either.
OMARCHY_INSTALL_USER=ghost bash -eE "$ROOT/install/hardware/input-group.sh"
OMARCHY_INSTALL_USER=ghost bash -eE "$ROOT/install/config/browser-policy.sh"
[[ ! -f $TMPDIR/usermod.calls ]] || fail "usermod not called for a missing user"
pass "missing install user defers group grants"

# Re-running never duplicates entries.
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/hardware/input-group.sh"
[[ $(grep -cxF input "$OMARCHY_PROVISIONING_DIR/groups") == 1 ]] || fail "input group recorded once"
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/config/browser-policy.sh"
pass "group recording is idempotent"

# Existing user: usermod applies the recorded groups, and docker is never among them.
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/config/docker.sh"
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/hardware/input-group.sh"
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/config/browser-policy.sh"
grep -qx -- "-aG input existing" "$TMPDIR/usermod.calls" || fail "usermod grants input to the install user"
! grep -q -- "omarchy-browser-policy" "$TMPDIR/usermod.calls" ||
  fail "usermod must not grant browser-policy to the install user"
! grep -q -- "docker" "$TMPDIR/usermod.calls" || fail "usermod must not grant docker to the install user"
pass "existing install user gets input but never docker or browser-policy"
