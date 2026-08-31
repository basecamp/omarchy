#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mise_log="$test_tmp/mise-log"
openclaw_log="$test_tmp/openclaw-log"
mkdir -p "$mock_bin" "$test_home/.local/bin"

# `mise where` decides whether OpenClaw is installed, so it is the switch the
# tests flip. Everything else records what it was asked to do.
cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_MISE_LOG"
[[ $1 == "where" ]] && exit "${OMARCHY_TEST_MISE_WHERE:-1}"
exit 0
SH

cat >"$mock_bin/openclaw" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_OPENCLAW_LOG"
SH

chmod +x "$mock_bin"/*

install() {
  OMARCHY_TEST_MISE_WHERE="${OMARCHY_TEST_MISE_WHERE:-1}" \
    OMARCHY_TEST_MISE_LOG="$mise_log" \
    OMARCHY_TEST_OPENCLAW_LOG="$openclaw_log" \
    HOME="$test_home" \
    PATH="$mock_bin:$PATH" \
    bash "$ROOT/bin/omarchy-install-ai-openclaw" ${1:+"$1"} >/dev/null 2>&1
}

onboard() {
  mkdir -p "$test_home/.openclaw"
  printf '{}\n' >"$test_home/.openclaw/openclaw.json"
}

logged() {
  tr '\0' ' ' <"$1" | grep -q "$2"
}

# A stub is on PATH from first boot, so being able to run `openclaw` says
# nothing about there being an OpenClaw behind it.
rm -rf "$test_home/.openclaw"
OMARCHY_TEST_MISE_WHERE=1 install --check &&
  fail "--check reports OpenClaw missing when only the cold stub is there"
pass "--check does not mistake the stub for an install"

# The install unpacks several stages before onboarding writes the config, and
# without the config there is no gateway to answer the terminal UI.
OMARCHY_TEST_MISE_WHERE=0 install --check &&
  fail "--check waits for onboarding, not just for the install"
pass "--check holds out for onboarding"

onboard
OMARCHY_TEST_MISE_WHERE=0 install --check ||
  fail "--check reports OpenClaw present once it is installed and onboarded"
pass "--check follows a finished setup"

# Setting OpenClaw as the default agent runs the installer on the way to
# launching it, so a machine already set up must not sit through it again.
: >"$mise_log"
: >"$openclaw_log"
OMARCHY_TEST_MISE_WHERE=0 install || fail "installing over a finished setup succeeds"
logged "$mise_log" "use -g" && fail "a finished setup is not reinstalled"
logged "$openclaw_log" "onboard" && fail "a finished setup is not onboarded again"
pass "installing over a finished setup does nothing"

# Onboarding is what leaves the gateway running; installing the command alone
# would put OpenClaw on PATH with nothing behind it to answer.
rm -rf "$test_home/.openclaw"
: >"$mise_log"
: >"$openclaw_log"
OMARCHY_TEST_MISE_WHERE=1 install || fail "installing from nothing succeeds"
logged "$mise_log" "use -g npm:openclaw" || fail "installing from nothing installs the CLI"
logged "$openclaw_log" "onboard --install-daemon" ||
  fail "installing from nothing sets the gateway up too"
pass "installing from nothing installs OpenClaw and its gateway"

# The install can be there from an earlier run, or from `mise up`, with the
# setup never finished. That still needs onboarding, and nothing else.
onboard
rm -f "$test_home/.openclaw/openclaw.json"
: >"$mise_log"
: >"$openclaw_log"
OMARCHY_TEST_MISE_WHERE=0 install || fail "finishing an unonboarded install succeeds"
logged "$mise_log" "use -g" && fail "an install that is already there is not redone"
logged "$openclaw_log" "onboard --install-daemon" ||
  fail "an install that never onboarded is taken through it"
pass "an unfinished install is onboarded without being reinstalled"
