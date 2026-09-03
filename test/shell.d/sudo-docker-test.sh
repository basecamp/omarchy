#!/bin/bash
#
# omarchy-sudo-docker is the single answer to "does Docker need sudo", and it
# answers two different questions on purpose. The default asks whether this
# session can reach the socket, which is what decides if a command must elevate.
# --configured asks whether the account is set up for sudoless Docker, which is
# what the menu needs so it offers the toggle that can change state. Between
# enabling sudoless Docker and the reboot that grants the group, those disagree.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

command="$ROOT/bin/omarchy-sudo-docker"

# Stub id so the configured groups are controllable.
mkdir -p "$TMPDIR/bin"
cat >"$TMPDIR/bin/id" <<'STUB'
#!/bin/bash
printf '%s\n' "${STUB_GROUPS:-wheel input}"
STUB
chmod +x "$TMPDIR/bin/id"

# A writable stand-in means the socket is reachable; an unwritable one means it
# is not. Test the file mode rather than a live daemon.
reachable_socket="$TMPDIR/reachable.sock"
blocked_socket="$TMPDIR/blocked.sock"
touch "$reachable_socket" "$blocked_socket"
chmod 600 "$reachable_socket"
chmod 400 "$blocked_socket"

run() { # SOCKET GROUPS [--configured]
  env PATH="$TMPDIR/bin:$PATH" OMARCHY_DOCKER_SOCKET="$1" STUB_GROUPS="$2" USER=tester \
    bash "$command" ${3:+"$3"}
}

# Default mode follows the socket, not the group list.
run "$blocked_socket" "wheel input" || fail "an unreachable socket means Docker needs sudo"
run "$reachable_socket" "wheel input" && fail "a reachable socket means Docker does not need sudo"
pass "default mode answers from the socket this session can reach"

# A socket that isn't there at all still needs elevation (starting it is root work).
run "$TMPDIR/absent.sock" "wheel input docker" || fail "a missing socket means Docker needs sudo"
pass "a missing socket counts as needing sudo"

# --configured follows the account's groups, not the socket.
run "$blocked_socket" "wheel input docker" --configured && fail "a configured docker group means no sudo is needed"
run "$reachable_socket" "wheel input" --configured || fail "no docker group means sudo is needed"
pass "--configured answers from the account's groups"

# The window this split exists for: sudoless Docker has just been enabled, so the
# account carries the group while the running session still cannot use it. The
# menu must offer Remove (--configured says no sudo) while lazydocker and the
# Windows VM must still prompt (default says sudo).
run "$blocked_socket" "wheel input docker" || fail "the session still needs sudo before the reboot"
run "$blocked_socket" "wheel input docker" --configured && fail "the account is already configured for sudoless Docker"
pass "the two modes disagree between enabling sudoless Docker and the reboot"

# An unknown argument is a usage error, not a silent answer either way.
run "$reachable_socket" "wheel input" --bogus 2>/dev/null && fail "an unknown flag exits non-zero"
status=0
run "$reachable_socket" "wheel input" --bogus >/dev/null 2>&1 || status=$?
(( status == 2 )) || fail "an unknown flag exits 2, not the boolean 1"
pass "an unknown flag is a usage error"
