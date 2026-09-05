#!/bin/bash

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/omarchy-cmd-missing" <<'STUB'
#!/bin/bash
[[ ${CARDWIRE_MISSING:-0} == "1" ]]
STUB

cat >"$fake_bin/omarchy-pkg-present" <<'STUB'
#!/bin/bash
[[ ${LEGACY_SUPERGFX:-0} == "1" ]]
STUB

cat >"$fake_bin/sleep" <<'STUB'
#!/bin/bash
:
STUB

cat >"$fake_bin/gum" <<'STUB'
#!/bin/bash
printf 'gum %s\n' "$*" >>"$TEST_TMP/gum.log"
exit "${GUM_EXIT:-1}"
STUB

normal_cardwire() {
  cat >"$fake_bin/cardwire" <<'STUB'
#!/bin/bash

case "$1" in
get)
  attempts_file="$TEST_TMP/attempts"
  attempts=0
  [[ -f $attempts_file ]] && attempts=$(<"$attempts_file")
  attempts=$((attempts + 1))
  printf '%s\n' "$attempts" >"$attempts_file"

  if (( attempts < ${SUCCEED_ON_ATTEMPT:-999} )); then
    exit 1
  fi

  echo "Current Mode: ${CURRENT_MODE:-Hybrid}"
  echo "Available Mode: integrated, hybrid, smart"
  ;;
set)
  printf 'cardwire %s\n' "$*" >>"$TEST_TMP/cardwire.log"
  exit 0
  ;;
*)
  exit 64
  ;;
esac
STUB
}

normal_cardwire
chmod +x "$fake_bin"/*

run_toggle() {
  PATH="$fake_bin:$ROOT/bin:$PATH" bash "$ROOT/bin/omarchy-toggle-hybrid-gpu"
}

reset_state() {
  rm -f "$test_tmp/attempts" "$test_tmp/gum.log" "$test_tmp/cardwire.log" "$test_tmp/calls.log"
}

TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=3 run_toggle >/dev/null

[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query retries transient failures"
pass "hybrid GPU mode query recovers from a transient cardwired failure"

reset_state

set +e
error=$(
  TEST_TMP="$test_tmp" run_toggle 2>&1 >/dev/null
)
status=$?
set -e

(( status != 0 )) || fail "hybrid GPU mode query fails when cardwired stays unavailable"
[[ $(<"$test_tmp/attempts") == "3" ]] || fail "hybrid GPU mode query stops after three attempts"
grep -qF 'cardwired is not responding' <<<"$error" ||
  fail "hybrid GPU mode query explains how to diagnose cardwired" "$error"
pass "hybrid GPU mode query fails clearly instead of hanging"

reset_state

TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=1 CURRENT_MODE=Hybrid GUM_EXIT=0 run_toggle >/dev/null

grep -qF 'cardwire set integrated' "$test_tmp/cardwire.log" ||
  fail "hybrid GPU mode switch applies the integrated mode" "$(<"$test_tmp/cardwire.log")"
pass "hybrid GPU mode switch applies the integrated mode"

reset_state

TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=1 CURRENT_MODE=Smart GUM_EXIT=0 run_toggle >/dev/null

grep -qF 'cardwire set hybrid' "$test_tmp/cardwire.log" ||
  fail "hybrid GPU mode switch applies the hybrid mode" "$(<"$test_tmp/cardwire.log")"
pass "hybrid GPU mode switch applies the hybrid mode"

reset_state

cat >"$fake_bin/cardwire" <<'STUB'
#!/bin/bash
trap '' TERM
/usr/bin/sleep 30
STUB
chmod +x "$fake_bin/cardwire"

set +e
output=$(TEST_TMP="$test_tmp" PATH="$fake_bin:$ROOT/bin:$PATH" timeout 25s bash "$ROOT/bin/omarchy-toggle-hybrid-gpu" 2>&1)
status=$?
set -e

(( status != 124 )) || fail "hybrid GPU mode query terminates a blocked client"
(( status != 0 )) || fail "hybrid GPU mode query reports a blocked client as unavailable"
grep -qF 'cardwired is not responding' <<<"$output" ||
  fail "hybrid GPU mode query diagnoses a blocked client" "$output"
pass "hybrid GPU mode query kills a client that ignores the timeout signal"

normal_cardwire
cat >"$fake_bin/omarchy-pkg-add" <<'STUB'
#!/bin/bash
printf 'pkg-add %s\n' "$*" >>"$TEST_TMP/calls.log"
STUB
cat >"$fake_bin/sudo" <<'STUB'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$TEST_TMP/calls.log"
exec "$@"
STUB
cat >"$fake_bin/systemctl" <<'STUB'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$TEST_TMP/calls.log"
exit 0
STUB
cat >"$fake_bin/rm" <<'STUB'
#!/bin/bash
printf 'rm %s\n' "$*" >>"$TEST_TMP/calls.log"
exit 0
STUB
chmod +x "$fake_bin"/*

reset_state

CARDWIRE_MISSING=1 LEGACY_SUPERGFX=1 \
  TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=1 GUM_EXIT=1 run_toggle >/dev/null
calls=$(<"$test_tmp/calls.log")

grep -qF 'pkg-add cardwire' <<<"$calls" ||
  fail "hybrid GPU toggle installs cardwire when it is missing" "$calls"
grep -qF 'systemctl enable --now cardwired' <<<"$calls" ||
  fail "hybrid GPU toggle starts cardwired after installing cardwire" "$calls"
grep -qF 'systemctl disable --now supergfxd.service' <<<"$calls" ||
  fail "hybrid GPU toggle disables the superseded supergfxd daemon" "$calls"
grep -qF 'rm -f /etc/supergfxd.conf' <<<"$calls" ||
  fail "hybrid GPU toggle removes the old supergfxd config" "$calls"
grep -qF 'rm -rf /usr/lib/systemd/system-sleep/force-igpu' <<<"$calls" ||
  fail "hybrid GPU toggle removes the old force-igpu sleep hook" "$calls"
grep -qF 'rm -rf /etc/systemd/system/supergfxd.service.d' <<<"$calls" ||
  fail "hybrid GPU toggle removes the old supergfxd delay-start drop-in" "$calls"
pass "hybrid GPU migration installs cardwire and retires supergfxd"

reset_state

CARDWIRE_MISSING=0 LEGACY_SUPERGFX=1 \
  TEST_TMP="$test_tmp" SUCCEED_ON_ATTEMPT=1 GUM_EXIT=1 run_toggle >/dev/null
calls=$(<"$test_tmp/calls.log")

grep -qF 'pkg-add cardwire' <<<"$calls" &&
  fail "hybrid GPU toggle skips the install when cardwire is present" "$calls"
grep -qF 'systemctl disable --now supergfxd.service' <<<"$calls" ||
  fail "hybrid GPU toggle still retires supergfxd when cardwire is present" "$calls"
pass "hybrid GPU cleanup runs without reinstalling cardwire"
