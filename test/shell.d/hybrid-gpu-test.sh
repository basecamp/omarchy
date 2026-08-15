#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$fake_bin/sleep" <<'STUB'
#!/bin/bash
:
STUB

cat >"$fake_bin/gum" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_TMP/prompts"
exit "${CONFIRM_STATUS:-1}"
STUB

cat >"$fake_bin/lspci" <<'STUB'
#!/bin/bash

if [[ ${T2_HARDWARE:-0} == "1" ]]; then
  echo '00:02.0 VGA compatible controller [0300]: Intel Corporation UHD Graphics [8086:3e9b]'
  echo '03:00.0 VGA compatible controller [0300]: AMD Radeon Pro [1002:7340]'
  echo '04:00.1 Non-VGA unclassified device [0000]: Apple T2 Bridge [106b:1801]'
fi
STUB

cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
"$@"
STUB

cat >"$fake_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
command -v "$1" >/dev/null
STUB

# Both names, so the test never reaches a real one whichever branch is taken.
cat >"$fake_bin/limine-mkinitcpio" <<'STUB'
#!/bin/bash
echo rebuild >>"$TEST_TMP/rebuilds"
exit "${REBUILD_STATUS:-0}"
STUB

cat >"$fake_bin/mkinitcpio" <<'STUB'
#!/bin/bash
echo rebuild >>"$TEST_TMP/rebuilds"
exit "${REBUILD_STATUS:-0}"
STUB

cat >"$fake_bin/omarchy-system-reboot" <<'STUB'
#!/bin/bash
echo reboot >>"$TEST_TMP/reboots"
STUB

cat >"$fake_bin/supergfxctl" <<'STUB'
#!/bin/bash
attempts_file="$TEST_TMP/attempts"
attempts=0
[[ -f $attempts_file ]] && attempts=$(<"$attempts_file")
attempts=$((attempts + 1))
printf '%s\n' "$attempts" >"$attempts_file"

if (( attempts < ${SUCCEED_ON_ATTEMPT:-999} )); then
  exit 1
fi

echo Hybrid
STUB

chmod +x "$fake_bin"/*

gmux_conf="$test_tmp/modprobe.d/apple-gmux.conf"

TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 \
  OMARCHY_T2_GMUX_CONF="$gmux_conf" PATH="$fake_bin:$PATH" \
  bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

grep -Fxq 'options apple-gmux force_igd=y' "$gmux_conf" ||
  fail "T2 hybrid graphics can switch to integrated graphics"
grep -Fq 'Use only integrated GPU and reboot?' "$test_tmp/prompts" ||
  fail "T2 Intel mode uses the existing integrated GPU prompt"
[[ $(wc -l <"$test_tmp/reboots") == "1" ]] || fail "T2 Intel mode requests one reboot"
[[ $(wc -l <"$test_tmp/rebuilds") == "1" ]] ||
  fail "T2 Intel mode rebuilds the boot image so the new module option is read"
pass "T2 hybrid graphics switches to integrated mode"

: >"$test_tmp/prompts"
TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 \
  OMARCHY_T2_GMUX_CONF="$gmux_conf" PATH="$fake_bin:$PATH" \
  bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

grep -Fxq 'options apple-gmux force_igd=n' "$gmux_conf" ||
  fail "T2 hybrid graphics can switch to dedicated graphics"
grep -Fq 'Enable dedicated GPU and reboot?' "$test_tmp/prompts" ||
  fail "T2 AMD mode uses the existing dedicated GPU prompt"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] || fail "T2 AMD mode requests one reboot"
[[ $(wc -l <"$test_tmp/rebuilds") == "2" ]] ||
  fail "T2 AMD mode rebuilds the boot image so the new module option is read"
pass "T2 hybrid graphics switches back to dedicated mode"

: >"$test_tmp/prompts"
TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=1 \
  OMARCHY_T2_GMUX_CONF="$gmux_conf" PATH="$fake_bin:$PATH" \
  bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

grep -Fxq 'options apple-gmux force_igd=n' "$gmux_conf" ||
  fail "declining a T2 graphics switch preserves the selected mode"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] || fail "declining a T2 graphics switch skips reboot"
[[ $(wc -l <"$test_tmp/rebuilds") == "2" ]] ||
  fail "declining a T2 graphics switch skips the boot image rebuild"
pass "T2 hybrid graphics leaves a declined switch unchanged"

: >"$test_tmp/prompts"
set +e
error=$(
  TEST_TMP="$test_tmp" T2_HARDWARE=1 CONFIRM_STATUS=0 REBUILD_STATUS=1 \
    OMARCHY_T2_GMUX_CONF="$gmux_conf" PATH="$fake_bin:$PATH" \
    bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "a failed boot image rebuild fails the T2 graphics switch"
[[ $(wc -l <"$test_tmp/reboots") == "2" ]] ||
  fail "a failed boot image rebuild leaves the machine running"
grep -qF 'Not rebooting' <<<"$error" ||
  fail "a failed boot image rebuild says why nothing happened" "$error"
pass "T2 hybrid graphics does not reboot onto a boot image that failed to build"

TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=3 \
  PATH="$fake_bin:$PATH" bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" >/dev/null

[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query retries transient failures"
pass "hybrid GPU mode query recovers from a transient supergfxd failure"

rm -f "$test_tmp/attempts"

set +e
error=$(
  TEST_TMP="$test_tmp" \
    PATH="$fake_bin:$PATH" bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "hybrid GPU mode query fails when supergfxd stays unavailable"
[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query stops after three attempts"
grep -qF 'supergfxd is not responding' <<<"$error" ||
  fail "hybrid GPU mode query explains how to diagnose supergfxd" "$error"
pass "hybrid GPU mode query fails clearly instead of hanging"

cat >"$fake_bin/supergfxctl" <<'STUB'
#!/bin/bash
trap '' TERM
/usr/bin/sleep 30
STUB
chmod +x "$fake_bin/supergfxctl"

set +e
output=$(TEST_TMP="$test_tmp" PATH="$fake_bin:$PATH" timeout 25s bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1)
status=$?
set -e

(( status != 124 )) || fail "hybrid GPU mode query terminates a blocked client"
(( status != 0 )) || fail "hybrid GPU mode query reports a blocked client as unavailable"
grep -qF 'supergfxd is not responding' <<<"$output" ||
  fail "hybrid GPU mode query diagnoses a blocked client" "$output"
pass "hybrid GPU mode query kills a client that ignores the timeout signal"
