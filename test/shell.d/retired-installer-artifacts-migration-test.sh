#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1788025225.sh"
[[ -f $migration ]] || fail "the retired installer artifact migration exists at $migration"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# sudo runs the real command, so the removals act on the redirected directories
# below and the elevated calls land in the log beside it.
cat >"$test_dir/bin/sudo" <<'STUB'
#!/bin/bash

printf 'sudo %s\n' "$*" >>"$CALLS"
exec "$@"
STUB

cat >"$test_dir/bin/systemctl" <<'STUB'
#!/bin/bash

printf 'systemctl %s\n' "$*" >>"$CALLS"
if [[ $* == "daemon-reload" && -n ${FAIL_DAEMON_RELOAD_ONCE_MARKER:-} && ! -e $FAIL_DAEMON_RELOAD_ONCE_MARKER ]]; then
  touch "$FAIL_DAEMON_RELOAD_ONCE_MARKER"
  exit 1
fi
STUB

chmod +x "$test_dir/bin/"*

# A second stub directory where sudo cannot elevate, standing in for a run with
# no terminal to read a password from.
mkdir -p "$test_dir/failing-bin"
cat >"$test_dir/failing-bin/sudo" <<'STUB'
#!/bin/bash

echo "sudo: a terminal is required to read the password" >&2
exit 1
STUB
cp "$test_dir/bin/systemctl" "$test_dir/failing-bin/systemctl"
chmod +x "$test_dir/failing-bin/"*

export CALLS="$test_dir/calls"

sudoers_dir="$test_dir/sudoers.d"
systemd_dir="$test_dir/systemd"
home_dir="$test_dir/home"
first_run="$sudoers_dir/first-run"
tsui="$sudoers_dir/tsui"
plymouth_unit="$systemd_dir/omarchy-plymouth-shutdown.service"
machine_marker="$test_dir/machine-marker"
reload_needed_marker="$machine_marker.daemon-reload"

reset_machine() {
  rm -rf "$sudoers_dir" "$systemd_dir" "$home_dir" "$machine_marker" "$reload_needed_marker"
  mkdir -p "$sudoers_dir" "$systemd_dir" "$home_dir"
}

run_migration() {
  : >"$CALLS"

  HOME="$home_dir" \
    OMARCHY_SUDOERS_DIR="$sudoers_dir" \
    OMARCHY_SYSTEMD_SYSTEM_DIR="$systemd_dir" \
    OMARCHY_RETIRED_INSTALLER_ARTIFACTS_MARKER="$machine_marker" \
    PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# /etc/sudoers.d is 0750 root:root on a real machine, so the migration has to
# escalate merely to see whether either grant is there. An empty call log is
# therefore the wrong invariant: what must be absent unless a file really is
# Omarchy's is a removal, or a unit being disabled or reloaded.
assert_changed_nothing() {
  local label="$1"

  ! grep -qE '^(sudo rm|systemctl disable|systemctl daemon-reload)' "$CALLS" ||
    fail "$label" "$(cat "$CALLS")"
  pass "$label"
}

# The reads themselves must be elevated too. A plain [[ -f ]] or cat under a
# root-only directory returns nothing as the logged-in user, which would make the
# migration report success having looked at nothing at all.
assert_read_elevated() {
  local file="$1" label="$2"

  grep -qF "bash $file" "$CALLS" ||
    fail "$label" "$(cat "$CALLS")"
  grep -qF "sudo cat $file" "$CALLS" ||
    fail "$label" "$(cat "$CALLS")"
  pass "$label"
}

write_plymouth_unit() {
  cat >"$plymouth_unit" <<EOF
[Unit]
Description=Sync Plymouth Theme on Shutdown
DefaultDependencies=yes
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecStop=$1

[Install]
WantedBy=multi-user.target
EOF
}

# Every distinct body the first-run-mode installer wrote across its nine rewrites,
# oldest first. Only the later ones carry both Cmnd_Alias lines, so a predicate
# keyed on those would leave the earlier grants on disk. The last body is the one
# install/post-install/first-run-mode.sh shipped until it was retired: its cleanup
# alias names /usr/bin/rm as well as /bin/rm, and it still grants passwordless
# /usr/bin/systemctl.
first_run_variants=(
  'installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /bin/rm -f /home/installer/.local/state/omarchy/first-run.mode'
  'installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /bin/rm -f /etc/sudoers.d/first-run'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
installer ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
installer ALL=(ALL) NOPASSWD: /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
installer ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
installer ALL=(ALL) NOPASSWD: /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
installer ALL=(ALL) NOPASSWD: /usr/bin/tee /etc/udev/rules.d/*
installer ALL=(ALL) NOPASSWD: /usr/bin/udevadm
installer ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
installer ALL=(ALL) NOPASSWD: /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
installer ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
  'Cmnd_Alias FIRST_RUN_CLEANUP = /usr/bin/rm -f /etc/sudoers.d/first-run, /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
installer ALL=(ALL) NOPASSWD: /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
installer ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
installer ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP'
)

variant=0
for body in "${first_run_variants[@]}"; do
  variant=$(( variant + 1 ))
  reset_machine
  printf '%s\n' "$body" >"$first_run"
  run_migration

  [[ ! -e $first_run ]] ||
    fail "migration removes first-run grant variant $variant" "$(cat "$first_run")"
done
pass "migration removes every first-run sudoers grant the installer ever wrote"

[[ -f $machine_marker ]] || fail "migration records the machine-wide repair"
pass "migration records the machine-wide repair"

grep -q '^sudo rm -f .*/sudoers\.d/first-run$' "$CALLS" ||
  fail "migration removes the first-run grant with elevated privileges" "$(cat "$CALLS")"
pass "migration removes the first-run grant with elevated privileges"

# The grant is only recognisable as Omarchy's because every line in it is one the
# installer emitted. One line an administrator added and the file is theirs.
reset_machine
cat >"$first_run" <<'EOF'
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
installer ALL=(ALL) NOPASSWD: /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: /usr/local/bin/our-own-deploy-script
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
before=$(cat "$first_run")
run_migration

[[ -e $first_run ]] || fail "migration keeps a first-run file carrying a hand-written rule"
[[ $(cat "$first_run") == "$before" ]] ||
  fail "migration leaves a hand-written first-run file byte for byte"
assert_changed_nothing "migration changes nothing for a hand-written first-run file"
pass "migration keeps a first-run file carrying a hand-written rule"

# The installer wrote one account name consistently. A whitelisted command for
# another user is an administrator extension, not part of the generated body.
reset_machine
printf '%s\n' "${first_run_variants[-1]}" >"$first_run"
printf '%%wheel ALL=(ALL) NOPASSWD: /usr/bin/systemctl\n' >>"$first_run"
before=$(cat "$first_run")
run_migration

[[ -e $first_run ]] || fail "migration keeps a generated file extended for another sudoers user"
[[ $(cat "$first_run") == "$before" ]] ||
  fail "migration leaves a generated file extended for another user byte for byte"
pass "migration does not delete an administrator grant that uses a generated command"

# The oldest installer variant expanded the same $USER into the sudoers account
# and the /home/<user>/ cleanup path. A different account in the path proves the
# line was edited or hand-written and makes the whole file administrator-owned.
reset_machine
cat >"$first_run" <<'EOF'
alice ALL=(ALL) NOPASSWD: /bin/rm -f /home/bob/.local/state/omarchy/first-run.mode
EOF
before=$(cat "$first_run")
run_migration

[[ -e $first_run ]] || fail "migration keeps a first-run cleanup path for another account"
[[ $(cat "$first_run") == "$before" ]] ||
  fail "migration leaves the cross-account first-run file byte for byte"
pass "migration requires the cleanup path account to match the granted account"

# Nothing in this file ties it to Omarchy's first run: no self-cleanup line.
reset_machine
cat >"$first_run" <<'EOF'
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw
installer ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
EOF
run_migration

[[ -e $first_run ]] ||
  fail "migration keeps a same-named file that never cleaned itself up"
pass "migration keeps a same-named file that never cleaned itself up"

# A spec continued onto the next line is one logical line, and a comment's own
# trailing backslash swallows nothing: `visudo -cf` on "# note \" plus a bogus
# token reports the error on line 2, so the spec below a commented line is live.
# The hand-written spec sits under the comment on purpose -- above it, the file
# is kept under either reading and the assertion cannot fail.
reset_machine
cat >"$first_run" <<'EOF'
# Retired, keeping the old grant here for reference: \
installer ALL=(ALL) NOPASSWD: /usr/local/bin/our-own-deploy-script
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
installer ALL=(ALL) NOPASSWD: \
    /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
run_migration

[[ -e $first_run ]] ||
  fail "migration keeps a spec left live under a commented continuation"
pass "migration keeps a spec left live under a commented continuation"

reset_machine
printf 'installer ALL=(ALL) NOPASSWD: %s/.local/bin/tsui\n' "$home_dir" >"$tsui"
run_migration

[[ ! -e $tsui ]] || fail "migration removes the tsui grant pointing into the user's home"
grep -q '^sudo rm -f .*/sudoers\.d/tsui$' "$CALLS" ||
  fail "migration removes the tsui grant with elevated privileges" "$(cat "$CALLS")"
pass "migration removes the tsui grant pointing into the user's home"

# The feature is gone from Omarchy either way, and unrestricted NOPASSWD on a TUI
# that can shell out escalates from a root-owned path too.
reset_machine
printf 'installer ALL=(ALL) NOPASSWD: /usr/bin/tsui\n' >"$tsui"
run_migration

[[ ! -e $tsui ]] || fail "migration removes the tsui grant wherever the path points"
pass "migration removes the tsui grant wherever the path points"

reset_machine
cat >"$tsui" <<'EOF'
# Kept after Omarchy dropped tsui, extended for our operators
installer ALL=(ALL) NOPASSWD: /usr/bin/tsui
operator ALL=(ALL) NOPASSWD: /usr/bin/tsui
EOF
before=$(cat "$tsui")
run_migration

[[ -e $tsui ]] || fail "migration keeps a tsui file an administrator extended"
[[ $(cat "$tsui") == "$before" ]] || fail "migration leaves an extended tsui file byte for byte"
assert_changed_nothing "migration changes nothing for an extended tsui file"
pass "migration keeps a tsui file an administrator extended"

reset_machine
printf 'installer ALL=(ALL) NOPASSWD: /usr/bin/tailscale\n' >"$tsui"
run_migration

[[ -e $tsui ]] || fail "migration keeps a lone grant for some other command"
pass "migration keeps a lone grant for some other command"

reset_machine
write_plymouth_unit "/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync"
run_migration

[[ ! -e $plymouth_unit ]] ||
  fail "migration removes the shutdown unit that runs out of a user home"
pass "migration removes the shutdown unit that runs out of a user home"

# Stopping the unit is exactly what runs ExecStop, which is the path being taken
# away from root. Disabling only drops the multi-user.target symlink.
! grep -q '^systemctl stop' "$CALLS" ||
  fail "migration never stops the unit, which would run ExecStop as root" "$(cat "$CALLS")"
pass "migration never stops the unit, which would run ExecStop as root"

disable_at=$(grep -n '^systemctl disable omarchy-plymouth-shutdown\.service$' "$CALLS" | cut -d: -f1)
remove_at=$(grep -n '^sudo rm -f .*omarchy-plymouth-shutdown\.service$' "$CALLS" | cut -d: -f1)
reload_at=$(grep -n '^systemctl daemon-reload$' "$CALLS" | cut -d: -f1)
[[ -n $disable_at && -n $remove_at && -n $reload_at ]] ||
  fail "migration disables, removes, then reloads the unit" "$(cat "$CALLS")"
(( disable_at < remove_at && remove_at < reload_at )) ||
  fail "migration disables before removing and reloads last" "$(cat "$CALLS")"
pass "migration disables the unit, removes it, then reloads systemd in that order"

# Homes are not all under /home, and the account running this machine-wide
# repair may not be the account that installed the unit.
reset_machine
write_plymouth_unit "/srv/retired-installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync"
run_migration

[[ ! -e $plymouth_unit ]] ||
  fail "migration removes another user's shutdown unit rooted outside /home"
[[ -e $machine_marker ]] || fail "migration marks the cross-user Plymouth repair complete"
pass "migration removes another user's shutdown unit rooted outside /home"

reset_machine
write_plymouth_unit "/usr/bin/omarchy-plymouth-shutdown-sync"
run_migration

[[ -e $plymouth_unit ]] ||
  fail "migration keeps a same-named unit that runs a packaged command"
assert_changed_nothing "migration changes nothing for a packaged shutdown unit"
pass "migration keeps a same-named unit that runs a packaged command"

# systemd takes ';' as a comment too, and an ExecStop behind one runs nothing.
reset_machine
cat >"$plymouth_unit" <<'EOF'
[Service]
Type=oneshot
; ExecStop=/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync
ExecStop=/usr/bin/true
EOF
run_migration

[[ -e $plymouth_unit ]] || fail "migration keeps a unit whose home ExecStop is commented out"
pass "migration keeps a unit whose home ExecStop is commented out"

# Non-empty ExecStop= assignments append; a packaged command after the retired
# home command does not replace it, so the vulnerable command remains live.
reset_machine
cat >"$plymouth_unit" <<'EOF'
[Service]
Type=oneshot
ExecStart=/usr/bin/true
ExecStop=/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync
ExecStop=/usr/bin/true
EOF
run_migration

[[ ! -e $plymouth_unit ]] ||
  fail "migration removes a home ExecStop followed by another command" "$(cat "$plymouth_unit")"
pass "migration removes a home ExecStop followed by another command"

reset_machine
run_migration

assert_changed_nothing "migration changes nothing when no retired artifact is present"
pass "migration leaves a machine without any retired artifact alone"

# All three at once, then the same run again: what a second account on the
# machine does, and what running omarchy-migrate twice does.
reset_machine
printf '%s\n' "${first_run_variants[-1]}" >"$first_run"
printf 'installer ALL=(ALL) NOPASSWD: /usr/bin/tsui\n' >"$tsui"
write_plymouth_unit "/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync"
run_migration

[[ ! -e $first_run && ! -e $tsui && ! -e $plymouth_unit ]] ||
  fail "migration clears all three retired artifacts in one pass"
pass "migration clears all three retired artifacts in one pass"

run_migration

assert_changed_nothing "migration changes nothing on a second run"
pass "migration is a no-op on a second run"

# sudo does not treat every '#' as a comment. plugins/sudoers/toke.l matches
# ^#include and ^#includedir as directives in the INITIAL state, and its comment
# rule excludes '#' followed by a digit or -digit so those reach the ID token as a
# numeric uid user spec -- sudoers(5) says the same. Dropping such a line as a
# comment would let a file that still carries an active directive read as though
# it held only generated lines, and be deleted.
for directive in \
  '#include /etc/sudoers.local' \
  '#includedir /etc/sudoers.d.local' \
  '#1000 ALL=(ALL) NOPASSWD: ALL' \
  '#-1000 ALL=(ALL) NOPASSWD: ALL'; do
  reset_machine
  {
    printf '%s\n' "$directive"
    printf '%s\n' "${first_run_variants[-1]}"
  } >"$first_run"
  before=$(cat "$first_run")
  run_migration

  [[ -e $first_run ]] ||
    fail "migration keeps a first-run file carrying the active directive $directive"
  [[ $(cat "$first_run") == "$before" ]] ||
    fail "migration leaves a first-run file with $directive byte for byte"
  pass "migration keeps a first-run file carrying the active directive $directive"

  reset_machine
  {
    printf '%s\n' "$directive"
    printf 'installer ALL=(ALL) NOPASSWD: /usr/bin/tsui\n'
  } >"$tsui"
  before=$(cat "$tsui")
  run_migration

  [[ -e $tsui ]] ||
    fail "migration keeps a tsui file carrying the active directive $directive"
  [[ $(cat "$tsui") == "$before" ]] ||
    fail "migration leaves a tsui file with $directive byte for byte"
  pass "migration keeps a tsui file carrying the active directive $directive"
done

# A sudoers comment ending in a backslash does not swallow the line beneath it:
# toke.l's comment rule consumes to the newline and clears the continuation flag.
# Joining before testing for a comment would hide this administrator's grant.
reset_machine
cat >"$tsui" <<'EOF'
# retired, kept for reference \
ops ALL=(ALL) NOPASSWD: /usr/bin/tsui
installer ALL=(ALL) NOPASSWD: /usr/bin/tsui
EOF
before=$(cat "$tsui")
run_migration

[[ -e $tsui ]] ||
  fail "migration keeps a tsui file whose second grant survives a commented continuation"
[[ $(cat "$tsui") == "$before" ]] ||
  fail "migration leaves that tsui file byte for byte"
pass "migration keeps a tsui file whose second grant survives a commented continuation"

# Both grants live under a root-only directory, so seeing them at all takes
# elevation. Pin that the migration reads them elevated rather than silently
# reading nothing.
reset_machine
printf '%s\n' "${first_run_variants[-1]}" >"$first_run"
run_migration

assert_read_elevated "$first_run" "migration reads the first-run grant with elevated privileges"

reset_machine
printf 'installer ALL=(ALL) NOPASSWD: /usr/bin/tsui\n' >"$tsui"
run_migration

assert_read_elevated "$tsui" "migration reads the tsui grant with elevated privileges"

# sudo ends a logical line at a comment and keeps what came before it: visudo -cf
# reads a spec ending in a backslash, then a comment, then a second spec as two
# live specs. Dropping the pending half would hide this administrator's grant and
# let the file read as though the installer had written all of it.
reset_machine
cat >"$first_run" <<'EOF'
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
operator ALL=(ALL) NOPASSWD: /usr/local/bin/deploy \
# kept deliberately
installer ALL=(ALL) NOPASSWD: /usr/bin/systemctl
installer ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
before=$(cat "$first_run")
run_migration

[[ -e $first_run ]] ||
  fail "migration keeps a first-run file whose hand-written spec precedes a comment"
[[ $(cat "$first_run") == "$before" ]] ||
  fail "migration leaves that first-run file byte for byte"
pass "migration keeps a first-run file whose hand-written spec precedes a comment"

reset_machine
cat >"$tsui" <<'EOF'
operator ALL=(ALL) NOPASSWD: /usr/local/bin/deploy \
# kept deliberately
installer ALL=(ALL) NOPASSWD: /usr/bin/tsui
EOF
before=$(cat "$tsui")
run_migration

[[ -e $tsui ]] ||
  fail "migration keeps a tsui file whose hand-written spec precedes a comment"
[[ $(cat "$tsui") == "$before" ]] ||
  fail "migration leaves that tsui file byte for byte"
pass "migration keeps a tsui file whose hand-written spec precedes a comment"

# systemd resumes a continuation across a comment: systemd-analyze verify on
# "ExecStop=\" + "; c" + a path resolves that path. The unit is live and has to go.
reset_machine
cat >"$plymouth_unit" <<'EOF'
[Service]
Type=oneshot
ExecStart=/usr/bin/true
ExecStop=\
; still one directive
/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync
EOF
run_migration

[[ ! -e $plymouth_unit ]] ||
  fail "migration removes a unit whose ExecStop continues across a comment" "$(cat "$plymouth_unit")"
pass "migration removes a unit whose ExecStop continues across a comment"

# An empty ExecStop= resets the list: `systemd-analyze verify` reports the missing
# command for a unit with one ExecStop=, and reports nothing once a bare
# ExecStop= follows it. An administrator who neutralised the unit that way runs
# nothing at shutdown and keeps their file.
reset_machine
cat >"$plymouth_unit" <<'EOF'
[Service]
Type=oneshot
ExecStart=/usr/bin/true
ExecStop=/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync
ExecStop=
EOF
before=$(cat "$plymouth_unit")
run_migration

[[ -e $plymouth_unit ]] ||
  fail "migration keeps a unit whose ExecStop list was reset to empty"
[[ $(cat "$plymouth_unit") == "$before" ]] ||
  fail "migration leaves that unit byte for byte"
pass "migration keeps a unit whose ExecStop list was reset to empty"

# A reset followed by a fresh home ExecStop= is live again.
reset_machine
cat >"$plymouth_unit" <<'EOF'
[Service]
Type=oneshot
ExecStart=/usr/bin/true
ExecStop=
ExecStop=/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync
EOF
run_migration

[[ ! -e $plymouth_unit ]] ||
  fail "migration removes a unit whose ExecStop is set again after a reset"
pass "migration removes a unit whose ExecStop is set again after a reset"

# systemd honours a directive whose line ends the file mid-continuation:
# `systemd-analyze verify` resolves an ExecStop= written that way.
reset_machine
printf '[Service]\nType=oneshot\nExecStart=/usr/bin/true\nExecStop=/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync \\\n' >"$plymouth_unit"
run_migration

[[ ! -e $plymouth_unit ]] ||
  fail "migration removes a unit whose last line ends mid-continuation"
pass "migration removes a unit whose last line ends mid-continuation"

# If removing the unit succeeds but daemon-reload fails, the loaded unit still
# needs to be forgotten. Persist that half of the repair so the retry reloads
# systemd even though the unit file is already gone.
reset_machine
write_plymouth_unit "/home/installer/.local/share/omarchy/bin/omarchy-plymouth-shutdown-sync"
reload_failure_seen="$test_dir/reload-failure-seen"
rm -f "$reload_failure_seen"

set +e
FAIL_DAEMON_RELOAD_ONCE_MARKER="$reload_failure_seen" run_migration
reload_status=$?
set -e

(( reload_status != 0 )) ||
  fail "migration fails after a failed daemon-reload" "status=$reload_status"
[[ ! -e $plymouth_unit && -e $reload_needed_marker && ! -e $machine_marker ]] ||
  fail "migration records the pending reload without marking the repair complete"

run_migration
[[ ! -e $reload_needed_marker && -e $machine_marker ]] ||
  fail "migration completes a pending daemon-reload on retry"
grep -q '^systemctl daemon-reload$' "$CALLS" ||
  fail "migration retries daemon-reload after the unit file is gone" "$(cat "$CALLS")"
pass "migration retries daemon-reload after the unit file is gone"

# sudo cannot prompt without a terminal, and omarchy-migrate runs from places that
# have none. bin/omarchy-migrate writes the completion marker on a zero exit, so
# reporting success after failing to look would mark this migration done for good.
# Observed on a real machine before this guard existed: the run printed sudo's
# "a terminal is required" and still exited 0.
reset_machine
readable="$test_dir/readable-sudoers"
rm -rf "$readable"
mkdir -p "$readable"
chmod 755 "$readable"
printf '%s\n' "${first_run_variants[-1]}" >"$readable/first-run"

: >"$CALLS"
set +e
HOME="$home_dir" \
  OMARCHY_SUDOERS_DIR="$readable" \
  OMARCHY_SYSTEMD_SYSTEM_DIR="$systemd_dir" \
  OMARCHY_RETIRED_INSTALLER_ARTIFACTS_MARKER="$machine_marker" \
  PATH="$test_dir/failing-bin:$PATH" \
  bash -euo pipefail "$migration" >"$test_dir/gate.out" 2>&1
gate_status=$?
set -e

(( gate_status != 0 )) ||
  fail "migration fails when it cannot elevate to inspect the sudoers directory" "status=$gate_status$(printf '\n%s' "$(cat "$test_dir/gate.out")")"
[[ -e $readable/first-run ]] ||
  fail "migration keeps a live grant when elevation fails"
[[ ! -e $machine_marker ]] ||
  fail "migration leaves the machine repair unmarked when elevation fails"
grep -q 'An administrator must run omarchy-migrate' "$test_dir/gate.out" ||
  fail "migration explains how the machine-wide repair can complete" "$(cat "$test_dir/gate.out")"
pass "migration fails without marking the machine repaired and names the administrator action"

# After one privileged account completes the machine repair, a non-sudo user
# can finish their per-user migration without probing sudo again.
touch "$machine_marker"
HOME="$home_dir" \
  OMARCHY_SUDOERS_DIR="$readable" \
  OMARCHY_SYSTEMD_SYSTEM_DIR="$systemd_dir" \
  OMARCHY_RETIRED_INSTALLER_ARTIFACTS_MARKER="$machine_marker" \
  PATH="$test_dir/failing-bin:$PATH" \
  bash -euo pipefail "$migration" >/dev/null
pass "machine marker lets a non-sudo user complete after the repair"
