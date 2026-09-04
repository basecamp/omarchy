#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1788513270.sh"
shipped="$ROOT/config/wireplumber/wireplumber.conf.d/audient-soft-mixer.conf"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/omarchy-restart-audio" <<'SH'
#!/bin/bash

echo 'omarchy-restart-audio' >>"$CALLS"
SH

cat >"$stub_bin/amixer" <<'SH'
#!/bin/bash

printf 'amixer %s\n' "$*" >>"$CALLS"
SH

chmod +x "$stub_bin"/*

export CALLS="$test_tmp/calls"

reset_machine() {
  test_home="$test_tmp/home"
  asound="$test_tmp/asound"

  rm -rf "$test_home" "$asound"
  mkdir -p "$test_home" "$asound"
}

add_card() {
  mkdir -p "$asound/card$1"
  printf '%s\n' "$2" >"$asound/card$1/usbid"
}

seeded_rule() {
  printf '%s/.config/wireplumber/wireplumber.conf.d/audient-soft-mixer.conf' "$test_home"
}

run_migration() {
  : >"$CALLS"

  HOME="$test_home" \
    OMARCHY_PATH="$ROOT" \
    OMARCHY_ALSA_PROCFS="$asound" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# An attached interface gets the rule, a restart to pick it up, and its mixer
# element put back where WirePlumber will no longer move it.
reset_machine
add_card 0 "8086:2668"
add_card 2 "2708:0002"
run_migration

cmp -s "$(seeded_rule)" "$shipped" ||
  fail "migration seeds the shipped rule"
pass "migration seeds the shipped rule"

grep -qx 'omarchy-restart-audio' "$CALLS" ||
  fail "migration restarts audio so the rule takes effect" "$(cat "$CALLS")"
pass "migration restarts audio so the rule takes effect"

grep -qx 'amixer -c 2 sset Speaker 100%' "$CALLS" ||
  fail "migration puts the interface mixer back to 0 dB" "$(cat "$CALLS")"
pass "migration puts the interface mixer back to 0 dB"

if grep -q 'amixer -c 0' "$CALLS"; then
  fail "migration leaves cards from other vendors alone" "$(cat "$CALLS")"
fi
pass "migration leaves cards from other vendors alone"

# The rule is inert without the hardware, so it is seeded anyway and nothing
# else on the machine gets disturbed for it.
reset_machine
add_card 0 "8086:2668"
run_migration

cmp -s "$(seeded_rule)" "$shipped" ||
  fail "migration seeds the rule with no interface attached"
pass "migration seeds the rule with no interface attached"

[[ ! -s $CALLS ]] ||
  fail "migration touches no audio state with no interface attached" "$(cat "$CALLS")"
pass "migration touches no audio state with no interface attached"

# Someone who already wrote this rule by hand keeps their version.
reset_machine
add_card 2 "2708:0002"
mkdir -p "$(dirname "$(seeded_rule)")"
printf '# hand written\n' >"$(seeded_rule)"
run_migration

grep -qx '# hand written' "$(seeded_rule)" ||
  fail "migration keeps a hand-written rule" "$(cat "$(seeded_rule)")"
pass "migration keeps a hand-written rule"
