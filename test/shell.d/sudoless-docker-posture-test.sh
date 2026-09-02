#!/bin/bash
#
# Docker is root-equivalent, so no automatic path may grant it. Raw input access
# is likewise excluded unless a feature that explicitly needs it is installed.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# First-boot provisioning must not replay old privileged defaults.
mkdir -p "$TMPDIR/bin"
printf '#!/bin/bash\nexit 0\n' >"$TMPDIR/bin/getent" # every group "exists"
cat >"$TMPDIR/bin/pacman" <<'STUB'
#!/bin/bash
[[ $1 == "-Qq" ]] || exit 2
[[ " ${STUB_PACKAGES:-} " == *" $2 "* ]]
STUB
# The profile decides whether wheel is seeded at all.
cat >"$TMPDIR/bin/omarchy-profile-child" <<'STUB'
#!/bin/bash
[[ ${STUB_PROFILE:-default} == child ]]
STUB
chmod +x "$TMPDIR/bin/getent" "$TMPDIR/bin/pacman" "$TMPDIR/bin/omarchy-profile-child"
export PATH="$TMPDIR/bin:$PATH"

PROVISIONING_DIR="$TMPDIR/prov"
mkdir -p "$PROVISIONING_DIR"
printf 'wheel\ninput\ndocker\n' >"$PROVISIONING_DIR/groups"

# Load the real user_groups() from the provisioning command and run it.
eval "$(sed -n '/^user_groups() {/,/^}/p' "$ROOT/bin/omarchy-provision-owner")"
groups=$(user_groups)

[[ ",$groups," == *",wheel,"* ]] || fail "user_groups includes wheel on a default install"
[[ ",$groups," != *",input,"* ]] || fail "user_groups must not replay the blanket input grant"
[[ ",$groups," == *",docker,"* ]] && fail "user_groups must never grant the docker group"
pass "first-boot user_groups replays neither privileged default"

groups=$(STUB_PACKAGES=xpadneo-dkms user_groups)
[[ ",$groups," == *",input,"* ]] || fail "user_groups keeps input for installed controller support"
groups=$(STUB_PACKAGES=ydotool user_groups)
[[ ",$groups," == *",input,"* ]] || fail "user_groups keeps input for installed ydotool support"
pass "first-boot user_groups keeps deliberate input-group opt-ins"

# A child install's kid account never enters wheel: omarchy-parent apply gives
# it an explicit sudo grant instead. With no recorded group left, the list is
# empty rather than a stray comma useradd would choke on.
groups=$(STUB_PROFILE=child user_groups)
[[ ",$groups," != *",wheel,"* ]] || fail "user_groups keeps the kid account out of wheel on a child install"
[[ -z $groups ]] || fail "user_groups is empty on a child install with no recorded groups" "got: $groups"
groups=$(STUB_PROFILE=child STUB_PACKAGES=ydotool user_groups)
[[ $groups == "input" ]] || fail "user_groups lists deliberate opt-ins cleanly without wheel" "got: $groups"
pass "first-boot user_groups leaves the kid account out of wheel on a child install"

# The Quattro upgrade must not re-add the user to docker.
if rg -q 'usermod -aG docker' "$ROOT/bin/omarchy-upgrade-to-quattro"; then
  fail "omarchy-upgrade-to-quattro must not add the user to the docker group"
fi
pass "the Quattro upgrade does not grant the docker group"
