#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

if [[ -z ${OMARCHY_UPDATE_SEQUENCE_NS:-} ]]; then
  outer_uid=$(id -u)
  outer_gid=$(id -g)
  subuid=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
  subgid=$(awk -F: -v group="$(id -gn)" '$1 == group { print $2; exit }' /etc/subgid)
  if [[ -z $subuid || -z $subgid ]]; then
    pass "no subordinate uid/gid range; skipping authorized update-sequence test"
    exit 0
  fi
  exec unshare --user --mount \
    --map-users "0:$outer_uid:1" --map-users "1:$subuid:65536" \
    --map-groups "0:$outer_gid:1" --map-groups "1:$subgid:65536" \
    env OMARCHY_UPDATE_SEQUENCE_NS=setup bash "$0"
elif [[ $OMARCHY_UPDATE_SEQUENCE_NS == setup ]]; then
  mount -t tmpfs -o mode=0755 tmpfs /run
  namespace_tmp=$(mktemp -d -p /run omarchy-update-sequence.XXXXXXXX)
  chmod 0755 "$namespace_tmp"
  mkdir -p "$namespace_tmp/default/omarchy/sudo-no-update"
  cp "$ROOT/default/omarchy/sudo-no-update/sudo" "$namespace_tmp/default/omarchy/sudo-no-update/sudo"
  chmod 0755 "$namespace_tmp/default/omarchy/sudo-no-update/sudo"
  cat >"$namespace_tmp/fixed-sudo" <<'STUB'
#!/bin/bash
if [[ ${1:-} == "-h" ]]; then
  echo 'usage: sudo [-ABbEHkNnPS] command'
fi
exit 0
STUB
  chmod 0755 "$namespace_tmp/fixed-sudo"
  mount --bind "$namespace_tmp/fixed-sudo" /usr/bin/sudo
  mount -t tmpfs -o mode=0755 tmpfs /etc
  printf 'export OMARCHY_PATH="%s"\n' "$namespace_tmp" >/etc/omarchy.conf
  chmod 0644 /etc/omarchy.conf
  chown -R 1000:1000 "$namespace_tmp"

  set +e
  setpriv --reuid 1000 --regid 1000 --clear-groups \
    env OMARCHY_UPDATE_SEQUENCE_NS=run OMARCHY_AUTHORIZED_TEST_ROOT="$namespace_tmp" bash "$0"
  status=$?
  set -e

  umount /usr/bin/sudo
  umount /etc
  rm -rf "$namespace_tmp"
  umount /run
  exit "$status"
fi

test_tmp="$OMARCHY_AUTHORIZED_TEST_ROOT"
trap 'rm -rf "$test_tmp"/*' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

# Every step omarchy-update runs, recorded in order with the unattended flag it
# was handed. One of them can be told to fail.
steps=(
  omarchy-update-lock
  omarchy-update-requires-free-space
  omarchy-update-confirm
  omarchy-update-pkg-prune
  omarchy-snapshot
  omarchy-update-stay-awake
  omarchy-update-dev
  omarchy-update-keyring
  omarchy-update-system-pkgs
  omarchy-migrate
  omarchy-hook
  omarchy-update-aur-pkgs
  omarchy-update-mise
  omarchy-update-orphan-pkgs
  omarchy-update-analyze-logs
  omarchy-update-status
  omarchy-update-restart
)

for step in "${steps[@]}"; do
  cat >"$stub_bin/$step" <<'STUB'
#!/bin/bash
printf '%s unattended=%s\n' "${0##*/}" "${OMARCHY_UPDATE_UNATTENDED:-}" >>"$STEP_LOG"
[[ ${FAILING_STEP:-} != "${0##*/}" ]] || exit 1
STUB
  chmod +x "$stub_bin/$step"
done

# OMARCHY_UPDATE_LOGGED stands in for the script(1) wrapper the update re-execs
# itself under; the stubbed lock reports itself already held.
run_update() {
  : >"$test_tmp/steps"
  STEP_LOG="$test_tmp/steps" \
    FAILING_STEP="${FAILING_STEP:-}" \
    OMARCHY_UPDATE_LOGGED=1 \
    PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-update" "$@" >"$test_tmp/out" 2>"$test_tmp/err"
}

steps_run() {
  cut -d' ' -f1 "$test_tmp/steps"
}

# Every step of a whole update, in order. $1 asks for the one a person confirms.
# Stay Awake bookends the work, so it is here twice.
expected_steps() {
  printf '%s\n' \
    omarchy-update-lock \
    omarchy-update-requires-free-space \
    ${1:+omarchy-update-confirm} \
    omarchy-update-pkg-prune \
    omarchy-snapshot \
    omarchy-update-stay-awake \
    omarchy-update-dev \
    omarchy-update-keyring \
    omarchy-update-system-pkgs \
    omarchy-migrate \
    omarchy-update-orphan-pkgs \
    omarchy-update-analyze-logs \
    omarchy-update-status \
    omarchy-update-restart \
    omarchy-update-stay-awake \
    omarchy-update-aur-pkgs \
    omarchy-hook \
    omarchy-update-mise \
    omarchy-update-restart
}

run_update -y || fail "an update where everything works reports a failure"
diff <(expected_steps) <(steps_run) >"$test_tmp/order" ||
  fail "an update where everything works does not run every step in order" "$(cat "$test_tmp/order")"
pass "an update where every step works runs all of them, in order"

grep -q '^omarchy-update-system-pkgs unattended=1$' "$test_tmp/steps" ||
  fail "-y does not mark the update unattended"
run_update </dev/null || fail "a confirmed update reports a failure"
diff <(expected_steps confirmed) <(steps_run) >"$test_tmp/order" ||
  fail "a confirmed update runs a different set of steps" "$(cat "$test_tmp/order")"
grep -q '^omarchy-update-system-pkgs unattended=$' "$test_tmp/steps" ||
  fail "an update a person confirmed is treated as unattended"
pass "-y is what marks an update unattended, not the update itself"

# Migrations ship with the packages the upgrade installs and are written against
# them. Running them against what is still on disk is the failure this ordering
# exists to prevent, so the update stops where the packages did.
if FAILING_STEP=omarchy-update-system-pkgs run_update -y; then
  fail "an update whose packages did not upgrade passes for a whole one"
fi
for step in omarchy-migrate omarchy-hook omarchy-update-aur-pkgs omarchy-update-restart; do
  if grep -q "^$step " "$test_tmp/steps"; then
    fail "a blocked package upgrade still runs $step"
  fi
done
pass "a blocked package upgrade stops the update before it migrates"
