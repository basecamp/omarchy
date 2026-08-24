#!/bin/bash
#
# The docker-group opt-in migration must remove an existing install's user from
# the root-equivalent docker group (only when they are in it), refresh the stale
# Docker launcher entry, and stay idempotent on reruns.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

migration="$ROOT/migrations/1787580187.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
omarchy_path="$test_dir/omarchy"
stub_bin="$test_dir/bin"
mkdir -p "$home/.local/share/applications" "$omarchy_path/applications" "$stub_bin"

# The packaged (new) launcher entry the migration should copy over the stale one.
printf 'NEW-LAUNCHER\n' >"$omarchy_path/applications/Docker.desktop"
printf 'OLD-LAUNCHER\n' >"$home/.local/share/applications/Docker.desktop"

# Stub id to report a controllable group set, and the removal command to record
# that it was called instead of touching the real system.
cat >"$stub_bin/id" <<'STUB'
#!/bin/bash
# Only the migration's `id -nG "$USER"` needs answering here.
printf '%s\n' "${STUB_GROUPS:-wheel input}"
STUB
cat >"$stub_bin/omarchy-remove-security-sudoless-docker" <<'STUB'
#!/bin/bash
touch "${REMOVE_CALLED:?}"
STUB
chmod +x "$stub_bin/id" "$stub_bin/omarchy-remove-security-sudoless-docker"

remove_called="$test_dir/remove-called"
run_migration() {
  rm -f "$remove_called"
  HOME="$home" OMARCHY_PATH="$omarchy_path" USER="tester" \
    STUB_GROUPS="$1" REMOVE_CALLED="$remove_called" \
    PATH="$stub_bin:$PATH" bash -euo pipefail "$migration" >/dev/null 2>&1
}

# In the docker group: the user is removed and the launcher is refreshed.
run_migration "wheel input docker" || fail "migration runs when the user is in the docker group"
[[ -e $remove_called ]] || fail "migration removes a user who is in the docker group"
[[ $(cat "$home/.local/share/applications/Docker.desktop") == "NEW-LAUNCHER" ]] ||
  fail "migration refreshes the stale Docker launcher entry"
pass "migration removes the docker group and refreshes the launcher"

# Not in the docker group (fresh install, or already migrated): no removal.
printf 'OLD-LAUNCHER\n' >"$home/.local/share/applications/Docker.desktop"
run_migration "wheel input" || fail "migration runs when the user is not in the docker group"
[[ ! -e $remove_called ]] || fail "migration must not call the removal when the user is not in the docker group"
[[ $(cat "$home/.local/share/applications/Docker.desktop") == "NEW-LAUNCHER" ]] ||
  fail "migration still refreshes the launcher when the group is already absent"
pass "migration is a no-op on the group when it is already absent"

# No launcher entry present: the refresh is skipped without error.
rm -f "$home/.local/share/applications/Docker.desktop"
run_migration "wheel input" || fail "migration tolerates a missing launcher entry"
[[ ! -e $home/.local/share/applications/Docker.desktop ]] ||
  fail "migration does not create a launcher entry that was not there"
pass "migration skips the launcher refresh when no entry exists"
