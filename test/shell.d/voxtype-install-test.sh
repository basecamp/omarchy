#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
mkdir -p "$mock_bin"

export REAL_GREP
REAL_GREP=$(command -v grep)

cat >"$mock_bin/grep" <<'SH'
#!/bin/bash
if [[ $* == *"/proc/cpuinfo"* ]]; then
  [[ ${OMARCHY_TEST_AVX2:-false} == "true" ]]
else
  exec "$REAL_GREP" "$@"
fi
SH

for command in gum omarchy-pkg-add voxtype hyprctl omarchy-restart-shell omarchy-notification-send; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s:%s\n' "$(basename "$0")" "$*" >>"$OMARCHY_TEST_CALL_LOG"
SH
done
cat >"$mock_bin/omarchy-hw-vulkan" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

if HOME="$test_tmp/home" OMARCHY_PATH="$ROOT" OMARCHY_TEST_CALL_LOG="$call_log" \
  PATH="$mock_bin:$PATH" bash "$ROOT/bin/omarchy-voxtype-install" \
  >"$test_tmp/output" 2>&1; then
  fail "Voxtype installer rejects CPUs without AVX2"
fi

grep -Fq "Voxtype Dictation requires AVX2" "$test_tmp/output" ||
  fail "Voxtype installer explains the AVX2 requirement" "$(cat "$test_tmp/output")"
[[ ! -s $call_log ]] ||
  fail "Voxtype installer stops before prompting or installing on an incompatible CPU" "$(cat "$call_log")"
pass "Voxtype installer rejects incompatible CPUs before prompting or installing"

: >"$call_log"
HOME="$test_tmp/home" OMARCHY_PATH="$ROOT" OMARCHY_TEST_CALL_LOG="$call_log" \
  OMARCHY_TEST_AVX2=true PATH="$mock_bin:$PATH" \
  bash "$ROOT/bin/omarchy-voxtype-install"

grep -Fq "gum:confirm Install Voxtype + AI model (~150MB) to enable dictation?" "$call_log" ||
  fail "Voxtype installer still prompts on compatible CPUs" "$(cat "$call_log")"
grep -Fq "omarchy-pkg-add:wtype voxtype-bin" "$call_log" ||
  fail "Voxtype installer still installs its packages on compatible CPUs" "$(cat "$call_log")"
grep -Fq "voxtype:setup --download --no-post-install" "$call_log" ||
  fail "Voxtype installer still downloads its model on compatible CPUs" "$(cat "$call_log")"
pass "Voxtype installer keeps the existing setup flow on AVX2 CPUs"
