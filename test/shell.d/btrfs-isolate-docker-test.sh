#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/bin/omarchy-btrfs-isolate-docker"
migration="$ROOT/migrations/1788028303.sh"
docker_install="$ROOT/install/config/docker.sh"
factory_finish="$ROOT/bin/omarchy-system-factory-reset-finish"
factory_unit="$ROOT/install/provisioning/omarchy-system-factory-reset-finish.service"

[[ -x $helper ]] || fail "omarchy-btrfs-isolate-docker is executable"
pass "omarchy-btrfs-isolate-docker is executable"

grep -q 'subvol=/@docker' "$helper" || fail "helper mounts the top-level @docker subvolume"
grep -q 'subvolid=5' "$helper" || fail "helper creates @docker on the btrfs top level"
grep -q -- '--migrate' "$helper" || fail "helper supports migrating an existing docker tree"
grep -q 'root_is_omarchy_btrfs' "$helper" || fail "helper gates on the Omarchy @ root layout"
pass "helper creates and mounts a top-level @docker subvolume"

# Nested-under-@ would be orphaned when limine-snapper-restore renames @; the
# helper must not use that pattern.
if grep -qE 'btrfs subvolume create .*/var/lib/docker' "$helper"; then
  fail "helper must not nest docker under @ (orphaned on root rename/rollback)"
fi
pass "helper does not nest docker under the root subvolume"

grep -F 'omarchy-btrfs-isolate-docker' "$docker_install" >/dev/null ||
  fail "install/config/docker.sh invokes the isolation helper before docker starts"
pass "install/config/docker.sh invokes the isolation helper"

grep -F 'omarchy-btrfs-isolate-docker --migrate' "$migration" >/dev/null ||
  fail "migration migrates existing docker data onto @docker"
grep -F 'OMARCHY_DOCKER_SUBVOL_MIGRATION_MARKER' "$migration" >/dev/null ||
  fail "migration records a machine-wide completion marker"
pass "migration migrates existing installs idempotently"

grep -F 'var-lib-docker.mount' "$factory_unit" >/dev/null ||
  fail "factory-reset finish waits for var-lib-docker.mount"
grep -F '@docker' "$factory_finish" >/dev/null ||
  fail "factory-reset finish recreates @docker"
pass "factory reset wipes @docker with the rest of the machine"

grep -F '@docker' "$ROOT/manual/47-system-snapshots.md" >/dev/null ||
  fail "snapshot manual documents docker isolation"
grep -F 'omarchy-btrfs-isolate-docker --migrate' "$ROOT/manual/47-system-snapshots.md" >/dev/null ||
  fail "snapshot manual points existing installs at the migrate command"
pass "snapshot manual documents docker isolation"

# Migration on a non-btrfs host: mark complete, do not invoke the helper.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/findmnt" <<'STUB'
#!/bin/bash
if [[ $* == *FSTYPE* ]]; then
  printf 'ext4\n'
  exit 0
fi
exit 1
STUB
cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
chmod +x "$test_tmp/bin"/*

marker="$test_tmp/marker"
PATH="$test_tmp/bin:/usr/bin:/bin" \
  OMARCHY_DOCKER_SUBVOL_MIGRATION_MARKER="$marker" \
  bash "$migration"
[[ -f $marker ]] || fail "migration marks non-btrfs installs complete without isolating"
pass "migration marks non-btrfs installs complete without isolating"

# Already-marked migration is a no-op even on btrfs.
cat >"$test_tmp/bin/findmnt" <<'STUB'
#!/bin/bash
if [[ $* == *FSTYPE* ]]; then
  printf 'btrfs\n'
  exit 0
fi
if [[ $* == *OPTIONS* ]]; then
  printf 'rw,relatime,subvol=/@\n'
  exit 0
fi
exit 1
STUB
cat >"$test_tmp/bin/omarchy-btrfs-isolate-docker" <<'STUB'
#!/bin/bash
echo "helper-ran" >>"${HELPER_LOG:?}"
STUB
chmod +x "$test_tmp/bin/omarchy-btrfs-isolate-docker" "$test_tmp/bin/findmnt"
helper_log="$test_tmp/helper-log"
PATH="$test_tmp/bin:/usr/bin:/bin" \
  OMARCHY_DOCKER_SUBVOL_MIGRATION_MARKER="$marker" \
  HELPER_LOG="$helper_log" \
  bash "$migration"
[[ ! -f $helper_log ]] || fail "migration must not re-run after the machine marker exists"
pass "migration is a no-op once the machine marker exists"

# First run on an Omarchy btrfs root invokes --migrate.
rm -f "$marker" "$helper_log"
cat >"$test_tmp/bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$test_tmp/bin/omarchy-cmd-missing"
PATH="$test_tmp/bin:/usr/bin:/bin" \
  OMARCHY_DOCKER_SUBVOL_MIGRATION_MARKER="$marker" \
  HELPER_LOG="$helper_log" \
  bash "$migration"
[[ -f $helper_log ]] || fail "migration runs the helper on an Omarchy btrfs root"
grep -q helper-ran "$helper_log" || fail "migration ran the isolation helper"
[[ -f $marker ]] || fail "migration writes the machine marker after success"
pass "migration runs the helper once on an Omarchy btrfs root"

# Helper refuses non-root (skip when the suite itself is already root).
if ((EUID != 0)); then
  if "$helper" >/dev/null 2>&1; then
    fail "helper must refuse to run as a non-root user"
  fi
  pass "helper refuses to run as a non-root user"
else
  pass "helper refuses to run as a non-root user (skipped under root)"
fi
