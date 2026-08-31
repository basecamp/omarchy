#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mise_log="$test_tmp/mise-log"
openclaw_log="$test_tmp/openclaw-log"
mkdir -p "$mock_bin"

cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_MISE_LOG"
SH

# A machine that never finished onboarding has no gateway service to give up,
# and OpenClaw says so by failing.
cat >"$mock_bin/openclaw" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_OPENCLAW_LOG"
exit "${OMARCHY_TEST_GATEWAY_EXIT:-0}"
SH

chmod +x "$mock_bin"/*

seed_install() {
  rm -rf "$test_home"
  mkdir -p "$test_home/.openclaw/sessions" "$test_home/.openclaw/skills" "$test_home/.local/bin"
  printf '{}\n' >"$test_home/.openclaw/openclaw.json"
  printf 'chat\n' >"$test_home/.openclaw/sessions/one.json"
  printf 'skill\n' >"$test_home/.openclaw/skills/one.md"

  # What omarchy-mise-install leaves on every machine: a stub that installs
  # OpenClaw the first time someone runs it.
  printf '%s\n' "#!/bin/bash" "mise use -g --quiet npm:openclaw || exit 1" \
    >"$test_home/.local/bin/openclaw"
  chmod +x "$test_home/.local/bin/openclaw"
}

remove() {
  OMARCHY_TEST_GATEWAY_EXIT="${OMARCHY_TEST_GATEWAY_EXIT:-0}" \
    OMARCHY_TEST_MISE_LOG="$mise_log" \
    OMARCHY_TEST_OPENCLAW_LOG="$openclaw_log" \
    HOME="$test_home" \
    PATH="$mock_bin:$PATH" \
    bash "$ROOT/bin/omarchy-remove-ai-openclaw" >/dev/null 2>&1
}

logged() {
  tr '\0' ' ' <"$1" | grep -q "$2"
}

seed_install
: >"$mise_log"
: >"$openclaw_log"
remove || fail "remove succeeds"

# The gateway is a systemd user service OpenClaw writes itself, so it is asked
# to take it back rather than having the unit unlinked behind it.
logged "$openclaw_log" "gateway uninstall" ||
  fail "removal hands the gateway service back to OpenClaw"
pass "removal asks OpenClaw to uninstall its own gateway service"

logged "$mise_log" "rm -g npm:openclaw" || fail "removal drops the global mise tool"
logged "$mise_log" "uninstall --all npm:openclaw" || fail "removal unpacks nothing back"
pass "removal takes the mise install with it"

# Leaving the cold stub puts the machine back where a fresh one starts rather
# than a step behind it: nothing runs until someone types openclaw again.
[[ -x $test_home/.local/bin/openclaw ]] ||
  fail "the stub every machine ships with survives removal"
pass "removal leaves the stub a fresh machine would have"

# The config names the inference provider, and the pairings took a round trip
# through each service to approve. None of it is ours to throw away.
[[ -f $test_home/.openclaw/openclaw.json ]] || fail "the config survives removal"
[[ -f $test_home/.openclaw/sessions/one.json ]] || fail "sessions survive removal"
[[ -f $test_home/.openclaw/skills/one.md ]] || fail "skills survive removal"
pass "removal keeps what belongs to the user"

# Installed but never onboarded: there is no service to uninstall, and that is
# not a failure to stop the rest of the removal.
seed_install
: >"$mise_log"
: >"$openclaw_log"
OMARCHY_TEST_GATEWAY_EXIT=1 remove || fail "remove succeeds with no gateway installed"
logged "$mise_log" "uninstall --all npm:openclaw" ||
  fail "a missing gateway service does not strand the mise install"
pass "removal finishes when there was no gateway to uninstall"
