#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1786873661.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
calls="$test_tmp/calls.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash

(( ${VOXTYPE_INSTALLED:-1} == 1 ))
SH

cat >"$stub_bin/omarchy-hw-vulkan" <<'SH'
#!/bin/bash

(( ${VULKAN_AVAILABLE:-1} == 1 ))
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash

printf 'sudo' >>"$TEST_LOG"
printf '\t%s' "$@" >>"$TEST_LOG"
printf '\n' >>"$TEST_LOG"
SH

cat >"$stub_bin/systemctl" <<'SH'
#!/bin/bash

if [[ "$1 $2 $3" == "--user is-active --quiet" ]]; then
  (( ${VOXTYPE_SERVICE_ACTIVE:-1} == 1 ))
else
  printf 'systemctl' >>"$TEST_LOG"
  printf '\t%s' "$@" >>"$TEST_LOG"
  printf '\n' >>"$TEST_LOG"
fi
SH

chmod +x "$stub_bin"/*

voxtype_lib="$test_tmp/lib"
voxtype_bin="$test_tmp/voxtype"
mkdir -p "$voxtype_lib"
touch "$voxtype_lib"/{voxtype-avx2,voxtype-avx512,voxtype-vulkan,voxtype-onnx-avx512}

set_backend() {
  ln -sfn "$voxtype_lib/$1" "$voxtype_bin"
}

run_migration() {
  PATH="$stub_bin:$PATH" \
    TEST_LOG="$calls" \
    OMARCHY_VOXTYPE_BIN="$voxtype_bin" \
    bash -euo pipefail "$migration" >/dev/null
}

sudo_enable=$'sudo\tvoxtype\tsetup\tgpu\t--enable'
service_restart=$'systemctl\t--user\trestart\tvoxtype'

# A CPU Whisper backend on Vulkan hardware is the state the buggy installer
# left behind: enable the GPU and restart the running service.
set_backend voxtype-avx512
: >"$calls"
run_migration

grep -Fxq "$sudo_enable" "$calls" ||
  fail "a CPU Whisper backend enables the GPU" "$(cat "$calls")"
grep -Fxq "$service_restart" "$calls" ||
  fail "an active voxtype service is restarted" "$(cat "$calls")"
pass "migration enables Vulkan and restarts an active service on a CPU backend"

set_backend voxtype-avx2
: >"$calls"
run_migration

grep -Fxq "$sudo_enable" "$calls" ||
  fail "the avx2 CPU backend is repaired too" "$(cat "$calls")"
pass "migration repairs both CPU Whisper backends"

# Without a running service there is nothing to restart; the enable still runs
# and the next login picks up the Vulkan binary.
: >"$calls"
VOXTYPE_SERVICE_ACTIVE=0 run_migration

grep -Fxq "$sudo_enable" "$calls" ||
  fail "an inactive service still gets the GPU enabled" "$(cat "$calls")"
if grep -Fxq "$service_restart" "$calls"; then
  fail "an inactive voxtype service is not restarted" "$(cat "$calls")"
fi
pass "migration skips the restart when the service is not running"

# Already on Vulkan: GPU setup ran before, nothing to repair.
set_backend voxtype-vulkan
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a Vulkan backend is left alone" "$(cat "$calls")"
pass "migration skips an install already on Vulkan"

# An ONNX target is a deliberate engine switch; forcing Vulkan would undo it.
set_backend voxtype-onnx-avx512
: >"$calls"
run_migration

[[ ! -s $calls ]] || fail "a deliberate ONNX engine switch is preserved" "$(cat "$calls")"
pass "migration preserves a deliberate ONNX engine switch"

set_backend voxtype-avx512

: >"$calls"
VOXTYPE_INSTALLED=0 run_migration

[[ ! -s $calls ]] || fail "installs without voxtype are skipped" "$(cat "$calls")"

: >"$calls"
VULKAN_AVAILABLE=0 run_migration

[[ ! -s $calls ]] || fail "machines without Vulkan are skipped" "$(cat "$calls")"
pass "migration skips installs it does not apply to"
