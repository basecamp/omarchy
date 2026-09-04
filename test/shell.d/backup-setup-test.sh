#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
fake_home="$test_tmp/home"
mkdir -p "$fake_bin" "$fake_home"

secrets_dir="$fake_home/.local/share/omarchy/backup"
config_dir="$fake_home/.config/omarchy/backup"
unit_dir="$fake_home/.config/systemd/user"
recovery_card="$fake_home/Omarchy Backup Recovery.txt"

printf 'correct-horse-battery-staple\n' >"$test_tmp/passphrase"

stub() {
  local name="$1"
  cat >"$fake_bin/$name"
  chmod +x "$fake_bin/$name"
}

stub restic <<'STUB'
#!/bin/bash
printf 'restic %s\n' "$*" >>"$TEST_LOG"
if [[ $1 == "cat" ]]; then
  exit "${STUB_PROBE_EXIT:-10}"
fi
exit 0
STUB

for command in omarchy-pkg-add omarchy-plugin-enable omarchy-plugin-disable systemctl gum fusermount; do
  stub "$command" <<STUB
#!/bin/bash
printf '$command %s\n' "\$*" >>"\$TEST_LOG"
exit 0
STUB
done

setup() {
  TEST_LOG="$test_tmp/calls.log" \
    HOME="$fake_home" \
    XDG_STATE_HOME="$fake_home/.local/state" \
    OMARCHY_PATH="$ROOT" \
    PATH="$fake_bin:$ROOT/bin:$PATH" \
    bash "$ROOT/bin/omarchy-setup-backup" "$@"
}

mode() {
  stat -c '%a' "$1"
}

: >"$test_tmp/calls.log"
setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null

# The repository is created only after the probe says there is nothing there.
grep -q '^restic cat config' "$test_tmp/calls.log" || fail "the destination is probed before anything is created"
grep -q '^restic init' "$test_tmp/calls.log" || fail "an absent repository is initialized"
pass "setup probes the destination and initializes only what is missing"

[[ $(mode "$secrets_dir") == "700" ]] || fail "the secrets directory is private" "$(mode "$secrets_dir")"
[[ $(mode "$secrets_dir/env") == "600" ]] || fail "the credentials file is private"
[[ $(mode "$secrets_dir/passphrase") == "600" ]] || fail "the passphrase file is private"
grep -q "RESTIC_REPOSITORY=$test_tmp/repo" "$secrets_dir/env" || fail "the repository is recorded"
! grep -q "correct-horse-battery-staple" "$secrets_dir/env" || fail "the passphrase does not leak into the environment file"
pass "credentials and passphrase are written privately, and separately"

# ~/.config is versioned and synced by people; a delete-capable credential must
# not ride along with it.
! grep -rq "correct-horse-battery-staple" "$config_dir" || fail "the passphrase is not in ~/.config"
! grep -rq "RESTIC_REPOSITORY" "$config_dir" 2>/dev/null || fail "credentials are not in ~/.config"
grep -q "BACKUP_MAINTENANCE_HOST=\"$(hostname)\"" "$config_dir/settings" ||
  fail "the machine that set the repository up owns maintenance" "$(cat "$config_dir/settings")"
pass "only non-secret settings land in ~/.config"

[[ -f $recovery_card ]] || fail "a recovery card is written"
[[ $(mode "$recovery_card") == "600" ]] || fail "the recovery card is private"
grep -q "$test_tmp/repo" "$recovery_card" || fail "the recovery card names the repository"
! grep -q "correct-horse-battery-staple" "$recovery_card" ||
  fail "the recovery card carries no live secret; the passphrase is written on by hand"
pass "the recovery card explains the restore without holding the keys"

[[ -L $unit_dir/omarchy-backup.timer ]] || fail "the timer is linked into the user's units"
[[ -L $unit_dir/omarchy-backup.service ]] || fail "the service is linked into the user's units"
grep -q 'systemctl --user enable --now omarchy-backup.timer' "$test_tmp/calls.log" || fail "the schedule is enabled"
grep -q 'omarchy-plugin-enable omarchy.backup' "$test_tmp/calls.log" || fail "the bar widget is placed"
pass "the schedule and the widget arrive together, at the end"

# Re-running the wizard must not double up or fail on what already exists.
: >"$test_tmp/calls.log"
setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null
[[ $(ls "$unit_dir" | wc -l) == "2" ]] || fail "re-running the setup does not duplicate units"
pass "the setup is idempotent"

# A passphrase that does not open an existing repository is a stop, not a
# reason to create a second repository next to the first.
: >"$test_tmp/calls.log"
set +e
STUB_PROBE_EXIT=12 setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null 2>"$test_tmp/stderr"
status=$?
set -e
(( status != 0 )) || fail "a wrong passphrase fails the setup"
grep -qi 'passphrase does not open' "$test_tmp/stderr" || fail "the wrong passphrase is named" "$(cat "$test_tmp/stderr")"
! grep -q '^restic init' "$test_tmp/calls.log" || fail "a wrong passphrase must not initialize anything"
pass "a wrong passphrase stops the setup without creating a repository"

: >"$test_tmp/calls.log"
set +e
STUB_PROBE_EXIT=1 setup --repository "$test_tmp/repo" --passphrase-file "$test_tmp/passphrase" --no-first-backup >/dev/null 2>"$test_tmp/stderr"
status=$?
set -e
(( status != 0 )) || fail "an unreachable destination fails the setup"
! grep -q '^restic init' "$test_tmp/calls.log" || fail "an unreachable destination must not initialize anything"
pass "an unreachable destination stops the setup without creating a repository"

: >"$test_tmp/calls.log"
setup --remove >"$test_tmp/removal"

grep -q 'systemctl --user disable omarchy-backup.timer' "$test_tmp/calls.log" || fail "removal disables the schedule"
grep -q 'omarchy-plugin-disable omarchy.backup' "$test_tmp/calls.log" || fail "removal takes the widget out of the bar"
[[ ! -e $secrets_dir ]] || fail "removal deletes the local credentials"
[[ ! -e $unit_dir/omarchy-backup.timer ]] || fail "removal unlinks the units"
grep -qi 'untouched' "$test_tmp/removal" || fail "removal says the backups themselves are still there" "$(cat "$test_tmp/removal")"
pass "removal forgets the destination without pretending to delete the backups"
