#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-pkg-drop" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_DROP_LOG"
SH

# The CLI teardown is the installer's own, exercised in hermes-cli-test.sh; here
# it is mocked to a logger so this test stays about what Remove Hermes does with
# ~/.hermes, and to keep real mise out of a run with HOME pointed at a fixture.
cat >"$mock_bin/omarchy-install-hermes-cli" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_INSTALLER_LOG"
exit "${OMARCHY_TEST_INSTALLER_STATUS:-0}"
SH

# The remover asks through gum whether the user's data should go too. The stub
# answers "no" unless a test says otherwise, and logs every call: a real gum
# would hang a test run, and one that answered "yes" on its own would be the
# very data loss the default-no exists to prevent.
cat >"$mock_bin/gum" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_GUM_LOG"
exit "${OMARCHY_TEST_GUM_STATUS:-1}"
SH
chmod +x "$mock_bin"/*

seed_install() {
  rm -rf "$test_home"
  mkdir -p "$test_home/.hermes/hermes-agent" "$test_home/.hermes/bootstrap-cache" \
    "$test_home/.hermes/bin" "$test_home/.hermes/node/bin" \
    "$test_home/.hermes/memories" "$test_home/.hermes/sessions" \
    "$test_home/.config/Hermes" "$test_home/.local/bin"
  printf 'chat\n' >"$test_home/.hermes/sessions/one.json"
  printf 'memory\n' >"$test_home/.hermes/memories/one.md"
  printf 'soul\n' >"$test_home/.hermes/SOUL.md"
  printf 'uv\n' >"$test_home/.hermes/bin/uv"
  ln -sf "$test_home/.hermes/node/bin/node" "$test_home/.local/bin/node"
  ln -sf "$test_home/.hermes/node/bin/npm" "$test_home/.local/bin/npm"
  ln -sf /usr/bin/npx "$test_home/.local/bin/npx"
  printf 'node\n' >"$test_home/.hermes/node/bin/node"
  touch "$test_home/.hermes/hermes-agent/.hermes-bootstrap-complete"
}

# </dev/null pins stdin off a terminal, so these runs exercise the
# non-interactive path no matter where the suite itself is running.
remove() {
  : >"$test_tmp/installer-log"
  : >"$test_tmp/gum-log"
  OMARCHY_TEST_DROP_LOG="$test_tmp/drop-log" \
    OMARCHY_TEST_INSTALLER_LOG="$test_tmp/installer-log" \
    OMARCHY_TEST_INSTALLER_STATUS="${OMARCHY_TEST_INSTALLER_STATUS:-0}" \
    OMARCHY_TEST_GUM_LOG="$test_tmp/gum-log" \
    HOME="$test_home" PATH="$mock_bin:$PATH" \
    bash "$ROOT/bin/omarchy-remove-ai-hermes" </dev/null >/dev/null 2>&1
}

# script(1) puts the remover on a pty, which is the only way -t 0 answers true
# without a person at a real one; the stubbed gum then supplies the answer.
remove_tty() {
  : >"$test_tmp/installer-log"
  : >"$test_tmp/gum-log"
  OMARCHY_TEST_DROP_LOG="$test_tmp/drop-log" \
    OMARCHY_TEST_INSTALLER_LOG="$test_tmp/installer-log" \
    OMARCHY_TEST_GUM_LOG="$test_tmp/gum-log" \
    OMARCHY_TEST_GUM_STATUS="${OMARCHY_TEST_GUM_STATUS:-1}" \
    HOME="$test_home" PATH="$mock_bin:$PATH" \
    script -qec "bash '$ROOT/bin/omarchy-remove-ai-hermes'" /dev/null >/dev/null 2>&1
}

# The app brings its own uv and its own node; both are runtime, not data.
seed_install
printf '%s\n' "#!/bin/bash" "exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds"
[[ ! -d $test_home/.hermes/hermes-agent ]] || fail "the runtime checkout is removed"
[[ ! -d $test_home/.hermes/bin ]] || fail "the uv the app installed is removed"
[[ ! -d $test_home/.hermes/node ]] || fail "the node the app installed is removed"
pass "removal takes the whole runtime the app installed"

[[ -d $test_home/.config/Hermes ]] ||
  fail "gateway connections, tokens and settings survive removal"
pass "removal keeps the app's connections and settings"

# -L, not -e: a dangling symlink fails -e while very much still being there.
[[ ! -L $test_home/.local/bin/node ]] || fail "a node symlink into ~/.hermes is removed"
[[ ! -L $test_home/.local/bin/npm ]] || fail "an npm symlink into ~/.hermes is removed"
[[ -L $test_home/.local/bin/npx ]] || fail "an npx symlink pointing elsewhere survives"
pass "removal clears only the managed Node links it stranded"

[[ -f $test_home/.hermes/sessions/one.json ]] || fail "chats survive removal"
[[ -f $test_home/.hermes/memories/one.md ]] || fail "memories survive removal"
[[ -f $test_home/.hermes/SOUL.md ]] || fail "SOUL.md survives removal"
pass "removal keeps what belongs to the user"

# Without a terminal there is nobody to ask, so gum must not even be reached:
# a gum that answered "yes" on its own would be a data loss.
[[ ! -s $test_tmp/gum-log ]] ||
  fail "removal does not ask about the user's data without a terminal"
pass "removal keeps the user's data unasked when there is no terminal"

[[ ! -e $test_home/.local/bin/hermes ]] || fail "the app's own hermes command is removed"
pass "removal takes the command the app installed"

# Removal also asks the installer to tear down a mise CLI the app superseded, so
# a copy left from before the app took over does not linger once Hermes is gone.
tr '\0' '\n' <"$test_tmp/installer-log" | grep -qx -- '--remove' ||
  fail "removal asks the installer to tear down its own CLI"
pass "removal tears down the mise CLI through the installer"

# A hermes command the app did not write survives even when the app did install
# a runtime of its own.
seed_install
printf '%s\n' "#!/bin/bash" "exec /usr/local/bin/my-own-hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds with a foreign hermes present"
[[ -f $test_home/.local/bin/hermes ]] ||
  fail "a hermes command the app did not write survives removal"
pass "removal leaves a hermes it does not own"

# Installed but never launched. The app provisions its runtime on first launch
# and marks it complete when it lands, so without that marker everything under
# ~/.hermes predates the app -- an official install, or one built by hand -- and
# the paths are identical either way. Dropping the package is the whole job.
seed_install
rm -f "$test_home/.hermes/hermes-agent/.hermes-bootstrap-complete"
printf 'my local edit\n' >"$test_home/.hermes/hermes-agent/PATCH"
printf '%s\n' "#!/bin/bash" "exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds when the app never finished installing Hermes"
# The stranded pre-desktop CLI is exactly the interrupted-install case, so the
# teardown must be asked for here too, not only when the app's runtime landed.
tr '\0' '\n' <"$test_tmp/installer-log" | grep -qx -- '--remove' ||
  fail "removal tears down the CLI even when the app never finished installing"
[[ -d $test_home/.hermes/hermes-agent ]] ||
  fail "a Hermes runtime the app never installed survives removal"
[[ -f $test_home/.hermes/hermes-agent/PATCH ]] ||
  fail "local changes to a runtime the app never installed survive removal"
[[ -d $test_home/.hermes/bin && -d $test_home/.hermes/node ]] ||
  fail "the rest of a runtime the app never installed survives removal"
[[ -f $test_home/.local/bin/hermes ]] ||
  fail "the command a runtime the app never installed put on PATH survives removal"
[[ -L $test_home/.local/bin/node ]] ||
  fail "node links belonging to a runtime the app never installed survive removal"
pass "removal leaves a Hermes the app never installed"

# ~/.hermes carries a dot, so a pattern rather than a plain string would also
# claim a wrapper pointing at a sibling directory that merely looks like it.
seed_install
mkdir -p "$test_home/xhermes/bin"
sibling_body="#!/bin/bash
exec $test_home/xhermes/bin/hermes \"\$@\""
printf '%s\n' "$sibling_body" >"$test_home/.local/bin/hermes"
remove || fail "remove succeeds with a wrapper pointing at a sibling directory"
[[ -f $test_home/.local/bin/hermes && $(cat "$test_home/.local/bin/hermes") == "$sibling_body" ]] ||
  fail "a wrapper pointing at ~/xhermes is not mistaken for one pointing into ~/.hermes"
pass "removal matches the runtime path as a plain string"

# On a terminal the user is asked, default no: declining leaves every piece of
# data where it was.
seed_install
remove_tty || fail "remove succeeds when the data question is declined"
tr '\0' '\n' <"$test_tmp/gum-log" | grep -qx 'confirm' ||
  fail "removal asks about the user's data on a terminal"
[[ -f $test_home/.hermes/sessions/one.json && -d $test_home/.config/Hermes ]] ||
  fail "declining the question keeps the user's data"
pass "removal asks on a terminal and declining keeps the data"

# An explicit yes is the one path that takes the data too.
seed_install
OMARCHY_TEST_GUM_STATUS=0 remove_tty || fail "remove succeeds when the data goes too"
[[ ! -e $test_home/.hermes && ! -e $test_home/.config/Hermes ]] ||
  fail "a yes deletes ~/.hermes and ~/.config/Hermes"
pass "removal deletes the user's data only on an explicit yes"

# Without the bootstrap marker ~/.hermes is an install the app never owned, so
# it must not even be offered for deletion -- not to a terminal, not to a user
# who would say yes.
seed_install
rm -f "$test_home/.hermes/hermes-agent/.hermes-bootstrap-complete"
OMARCHY_TEST_GUM_STATUS=0 remove_tty ||
  fail "remove succeeds when the app never installed Hermes"
[[ ! -s $test_tmp/gum-log ]] ||
  fail "a Hermes the app never installed is not offered for deletion"
[[ -d $test_home/.hermes/hermes-agent && -d $test_home/.config/Hermes ]] ||
  fail "a Hermes the app never installed survives a would-be yes"
pass "removal never offers a Hermes the app did not install"

# A CLI teardown that fails must not stop the runtime handling, and must not be
# papered over either: the data work still happens, and the failure reaches the
# caller's exit code.
seed_install
printf '%s\n' "#!/bin/bash" "exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\"" \
  >"$test_home/.local/bin/hermes"
OMARCHY_TEST_INSTALLER_STATUS=1 remove && fail "a failed CLI teardown surfaces in the exit code"
[[ ! -d $test_home/.hermes/hermes-agent ]] ||
  fail "a failed CLI teardown does not stop the runtime removal"
pass "a failed CLI teardown is reported after the runtime is handled"
