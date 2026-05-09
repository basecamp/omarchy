#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIRST_RUN_MODE="$ROOT/install/preflight/first-run-mode.sh"
REBOOT_CLEANUP="$ROOT/install/first-run/cleanup-reboot-sudoers.sh"
MIGRATION="$ROOT/migrations/1778347762.sh"

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

assert_readable_file() {
  local description="$1"
  local file="$2"

  if [[ ! -r $file ]]; then
    printf 'Expected readable file: %s\n' "$file" >&2
    fail "$description"
  fi
}

assert_contains() {
  local description="$1"
  local file="$2"
  local expected="$3"

  assert_readable_file "$description" "$file"

  if ! grep -Fqx "$expected" "$file"; then
    printf 'Expected line in %s:\n%s\n' "$file" "$expected" >&2
    fail "$description"
  fi

  pass "$description"
}

assert_not_contains() {
  local description="$1"
  local file="$2"
  local unexpected="$3"

  assert_readable_file "$description" "$file"

  if grep -Fqx "$unexpected" "$file"; then
    printf 'Unexpected line in %s:\n%s\n' "$file" "$unexpected" >&2
    fail "$description"
  fi

  pass "$description"
}

assert_contains "first-run permits only the needed root systemctl command" "$FIRST_RUN_MODE" \
  "Cmnd_Alias UFW_SERVICE_ENABLE = /usr/bin/systemctl enable ufw"
assert_contains "first-run uses the restricted systemctl alias" "$FIRST_RUN_MODE" \
  '$USER ALL=(ALL) NOPASSWD: UFW_SERVICE_ENABLE'
assert_not_contains "first-run does not permit unrestricted root systemctl" "$FIRST_RUN_MODE" \
  '$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl'

assert_contains "first-run permits reboot sudoers cleanup directly" "$FIRST_RUN_MODE" \
  "Cmnd_Alias INSTALLER_REBOOT_CLEANUP = /bin/rm -f /etc/sudoers.d/99-omarchy-installer-reboot"
assert_contains "first-run uses the reboot sudoers cleanup alias" "$FIRST_RUN_MODE" \
  '$USER ALL=(ALL) NOPASSWD: INSTALLER_REBOOT_CLEANUP'
assert_contains "reboot cleanup uses the permitted rm command" "$REBOOT_CLEANUP" \
  "sudo rm -f /etc/sudoers.d/99-omarchy-installer-reboot"
assert_not_contains "reboot cleanup does not require unpermitted sudo test" "$REBOOT_CLEANUP" \
  "if sudo test -f /etc/sudoers.d/99-omarchy-installer-reboot; then"

assert_contains "migration repairs active first-run sudoers" "$MIGRATION" \
  "echo \"Restrict first-run systemctl sudo access\""
assert_contains "migration writes the restricted systemctl alias" "$MIGRATION" \
  "Cmnd_Alias UFW_SERVICE_ENABLE = /usr/bin/systemctl enable ufw"
assert_contains "migration preserves the existing first-run sudoers user" "$MIGRATION" \
  '  first_run_user="$(sudo awk '\''/NOPASSWD:/ { print $1; exit }'\'' /etc/sudoers.d/first-run)"'
assert_contains "migration validates the extracted first-run user" "$MIGRATION" \
  '  if [[ -z $first_run_user ]]; then'
assert_not_contains "migration does not write unrestricted root systemctl" "$MIGRATION" \
  '$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl'
