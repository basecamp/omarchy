#!/bin/bash
#
# Privileged groups are never granted by the default install. Docker remains an
# explicit opt-in, and raw input-device access is granted only by the optional
# controller and ydotool installers.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export OMARCHY_PROVISIONING_DIR="$TMPDIR/provisioning"

mkdir -p "$TMPDIR/bin"
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
chmod +x "$TMPDIR/bin"/{usermod,groupadd,install,find,sudo}
export PATH="$TMPDIR/bin:$PATH"
export OMARCHY_PATH="$ROOT"

# A deferred-provisioning install records neither privileged group.
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/config/docker.sh"
OMARCHY_INSTALL_USER="" bash -eE "$ROOT/install/config/browser-policy.sh"

[[ ! -f $OMARCHY_PROVISIONING_DIR/groups ]] ||
  ! grep -Eq '^(docker|input)$' "$OMARCHY_PROVISIONING_DIR/groups" ||
  fail "default install must not record docker or input groups"
[[ ! -f $TMPDIR/usermod.calls ]] || fail "usermod not called without an install user"
[[ ! -f $TMPDIR/groupadd.calls ]] || ! grep -F omarchy-browser-policy "$TMPDIR/groupadd.calls" >/dev/null ||
  fail "browser-policy group is not created"
grep -F -- '-d -m 0755 -o root -g root /etc/chromium/policies/managed' "$TMPDIR/install.calls" >/dev/null ||
  fail "browser-policy directory is created root-owned"
pass "deferred provisioning records no privileged groups"

# The same remains true when an install user already exists.
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/config/docker.sh"
OMARCHY_INSTALL_USER=existing bash -eE "$ROOT/install/config/browser-policy.sh"
[[ ! -f $TMPDIR/usermod.calls ]] || fail "default install must not grant privileged groups"
pass "existing install user gets neither docker nor input access"

! grep -q 'hardware/input-group.sh' "$ROOT/install/hardware/all.sh" ||
  fail "hardware setup must not call the removed input-group grant"
[[ ! -e $ROOT/install/hardware/input-group.sh ]] || fail "blanket input-group grant is removed"
pass "hardware setup has no blanket input-group grant"
