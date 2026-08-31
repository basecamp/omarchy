#!/bin/bash

source "$(dirname "$0")/base-test.sh"

toggle="$ROOT/bin/omarchy-toggle-hybrid-gpu"
force_hook="$ROOT/default/systemd/system-sleep/force-igpu"
hibernation="$ROOT/bin/omarchy-hibernation-setup"

if grep -Eq 'cp .*systemd/system-sleep|rm -[^ ]*r[^ ]* .*systemd/system-sleep' "$toggle" "$hibernation"; then
  fail "runtime commands still create or recursively remove static hooks under /usr"
fi
grep -F 'force_igpu_marker=/etc/omarchy/force-igpu' "$toggle" >/dev/null ||
  fail "hybrid GPU mode has no runtime activation marker"
grep -F 'force_igpu_hook=/usr/lib/systemd/system-sleep/omarchy-force-igpu' "$toggle" >/dev/null ||
  fail "hybrid GPU mode does not use the package-owned hook"
grep -F 'delay_source=/usr/share/omarchy/default/systemd/system/supergfxd.service.d/delay-start.conf' "$toggle" >/dev/null ||
  fail "hybrid GPU mode does not use the package-owned delay source"
marker_line=$(grep -nF '[[ -f /etc/omarchy/force-igpu ]] || exit 0' "$force_hook" | cut -d: -f1)
case_line=$(grep -nF 'case "$1" in' "$force_hook" | cut -d: -f1)
[[ -n $marker_line && -n $case_line ]] && (( marker_line < case_line )) ||
  fail "the package-owned force-iGPU hook runs before checking its activation marker"
pass "hybrid GPU sleep behavior keeps executable code package-owned"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
source_root="$test_tmp/source"
test_command="$test_tmp/omarchy-toggle-hybrid-gpu"
mkdir -p "$fake_bin" "$source_root/bin" \
  "$source_root/default/systemd/system-sleep" \
  "$source_root/default/systemd/system/supergfxd.service.d"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
exit 1
STUB

cat >"$fake_bin/sleep" <<'STUB'
#!/bin/bash
:
STUB

cat >"$fake_bin/timeout" <<'STUB'
#!/bin/bash
exec /usr/bin/timeout "$@"
STUB

cat >"$fake_bin/gum" <<'STUB'
#!/bin/bash
exit 1
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

ln -s "$fake_bin/omarchy-cmd-missing" "$source_root/bin/omarchy-cmd-missing"
for command in omarchy-pkg-add omarchy-system-reboot; do
  cat >"$source_root/bin/$command" <<'STUB'
#!/bin/bash
:
STUB
  chmod 0755 "$source_root/bin/$command"
done
printf 'test hook\n' >"$source_root/default/systemd/system-sleep/force-igpu"
printf 'test override\n' >"$source_root/default/systemd/system/supergfxd.service.d/delay-start.conf"

# Source authorization/publication is covered in the focused security suite.
# This legacy test isolates only retry/timeout behavior by replacing the two
# resolver functions and fixed interactive/query executables in a scratch copy.
sed \
  -e '/^trusted_omarchy_source_root() {/,/^}/c\
trusted_omarchy_source_root() { printf '\''%s\\n'\'' "$OMARCHY_TEST_SOURCE_ROOT"; }' \
  -e '/^trusted_omarchy_source_file() {/,/^}/c\
trusted_omarchy_source_file() { printf '\''%s\\n'\'' "$OMARCHY_TEST_SOURCE_ROOT/$1"; }' \
  -e "s#/usr/bin/timeout#$fake_bin/timeout#g" \
  -e "s#/usr/bin/supergfxctl#$fake_bin/supergfxctl#g" \
  -e "s#/usr/bin/sleep#$fake_bin/sleep#g" \
  -e "s#/usr/bin/gum#$fake_bin/gum#g" \
  "$ROOT/bin/omarchy-toggle-hybrid-gpu" >"$test_command"
chmod 0755 "$test_command"

TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=3 \
  OMARCHY_TEST_SOURCE_ROOT="$source_root" bash "$test_command" >/dev/null

[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query retries transient failures"
pass "hybrid GPU mode query recovers from a transient supergfxd failure"

rm -f "$test_tmp/attempts"

set +e
error=$(
  TEST_TMP="$test_tmp" \
    OMARCHY_TEST_SOURCE_ROOT="$source_root" bash "$test_command" 2>&1 >/dev/null
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
output=$(TEST_TMP="$test_tmp" OMARCHY_TEST_SOURCE_ROOT="$source_root" timeout 25s bash "$test_command" 2>&1)
status=$?
set -e

(( status != 124 )) || fail "hybrid GPU mode query terminates a blocked client"
(( status != 0 )) || fail "hybrid GPU mode query reports a blocked client as unavailable"
grep -qF 'supergfxd is not responding' <<<"$output" ||
  fail "hybrid GPU mode query diagnoses a blocked client" "$output"
pass "hybrid GPU mode query kills a client that ignores the timeout signal"
