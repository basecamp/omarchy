#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
call_log="$test_tmp/calls"
mkdir -p "$mock_bin"

# The refresh copies the real shipped launchers; only what would reach the host
# is mocked, and every mock records its call.
for command in omarchy-mise-install omarchy-install-hermes-cli update-desktop-database; do
  cat >"$mock_bin/$command" <<SH
#!/bin/bash
printf '%s %s\n' "$command" "\$*" >>"\$OMARCHY_TEST_CALL_LOG"
SH
done
printf '#!/bin/bash\nexit 0\n' >"$mock_bin/omarchy-cmd-present"
chmod +x "$mock_bin"/*

export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_CALL_LOG="$call_log"

run_refresh() {
  local scenario=$1
  shift

  : >"$call_log"
  HOME="$test_tmp/$scenario" "$ROOT/bin/omarchy-refresh-applications" "$@" >/dev/null
}

launchers_in() {
  (cd "$test_tmp/$1/.local/share/applications" && ls -- *.desktop | sort)
}

wrapper_calls() {
  grep -c '^omarchy-mise-install \|^omarchy-install-hermes-cli' "$call_log" || true
}

# No opt-out on record: every shipped launcher, Alacritty's, and every wrapper.
mkdir -p "$test_tmp/fresh"
run_refresh fresh
shipped=$(cd "$ROOT/applications" && ls -- *.desktop | wc -l)
(( $(launchers_in fresh | wc -l) == shipped + 1 )) ||
  fail "refresh lays down every shipped launcher" "$(launchers_in fresh)"
(( $(wrapper_calls) > 0 )) || fail "refresh installs the wrappers" "$(cat "$call_log")"
pass "refresh restores every launcher and wrapper while preinstalls are in place"

# What Remove Preinstalls takes away from a full set is the reference for what
# the refresh must hold back once the opt-out is recorded.
reference="$test_tmp/reference"
mkdir -p "$reference"
cp "$test_tmp"/fresh/.local/share/applications/*.desktop "$reference/"
HOME="$test_tmp/fresh" omarchy-webapp-remove-all "$reference" >/dev/null
HOME="$test_tmp/fresh" omarchy-tui-remove-all "$reference" >/dev/null
expected=$(cd "$reference" && ls -- *.desktop | sort)

mkdir -p "$test_tmp/removed/.local/state/omarchy"
touch "$test_tmp/removed/.local/state/omarchy/preinstalls-removed"
run_refresh removed
[[ $(launchers_in removed) == "$expected" ]] ||
  fail "refresh holds back exactly the launchers Remove Preinstalls deletes" \
    "expected:
$expected
got:
$(launchers_in removed)"
for launcher in foot.desktop imv.desktop mpv.desktop Alacritty.desktop; do
  [[ -f $test_tmp/removed/.local/share/applications/$launcher ]] ||
    fail "refresh keeps the launchers Remove Preinstalls leaves alone" "$launcher missing"
done
(( $(wrapper_calls) == 0 )) || fail "refresh holds back the wrappers Remove Preinstalls deletes" "$(cat "$call_log")"
[[ -f $test_tmp/removed/.local/state/omarchy/preinstalls-removed ]] ||
  fail "refresh leaves the opt-out marker in place"
pass "refresh honours the preinstalls opt-out"

# Install Preinstalls runs the refresh while the marker still exists; asking by
# name brings everything back.
mkdir -p "$test_tmp/restore/.local/state/omarchy"
touch "$test_tmp/restore/.local/state/omarchy/preinstalls-removed"
run_refresh restore --with-preinstalls
[[ $(launchers_in restore) == "$(launchers_in fresh)" ]] ||
  fail "refresh --with-preinstalls restores every launcher" "$(launchers_in restore)"
(( $(wrapper_calls) > 0 )) || fail "refresh --with-preinstalls restores the wrappers" "$(cat "$call_log")"
pass "refresh restores the preinstalls when asked by name"
