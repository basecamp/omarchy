#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mise_log="$test_tmp/mise-log"
mkdir -p "$mock_bin" "$test_home/.local/bin"

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ ${OMARCHY_TEST_DESKTOP_INSTALLED:-0} == 1 ]]
SH

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
! command -v "$1" >/dev/null 2>&1
SH

# `mise where` must fail so the installer sees no Hermes behind the stub.
cat >"$mock_bin/mise" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >>"$OMARCHY_TEST_MISE_LOG"
[[ $1 == "where" && ${OMARCHY_TEST_MISE_WHERE_OK:-0} == 1 ]] && exit 0
[[ $1 != "where" ]]
SH

chmod +x "$mock_bin"/*

run_installer() {
  OMARCHY_TEST_DESKTOP_INSTALLED="$1" \
    OMARCHY_TEST_MISE_WHERE_OK="${OMARCHY_TEST_MISE_WHERE_OK:-0}" \
    OMARCHY_TEST_MISE_LOG="$mise_log" \
    HOME="$test_home" \
    PATH="$mock_bin:$PATH" \
    bash "$ROOT/bin/omarchy-install-hermes-cli" ${2:+"$2"} >/dev/null 2>&1
}

stub_marker="omarchy-install-hermes-cli"
app_stub_body='#!/bin/bash
exec /home/x/.hermes/hermes-agent/venv/bin/hermes "$@"'

# Writing the stub must not provision anything: user setup calls this on every
# machine, including the ones that never run Hermes.
: >"$mise_log"
rm -f "$test_home/.local/bin/hermes"
run_installer 0 || fail "installer failed with no desktop installed"
[[ -x $test_home/.local/bin/hermes ]] || fail "installer writes a hermes stub when the desktop is absent"
grep -q "$stub_marker" "$test_home/.local/bin/hermes" || fail "the stub records which command wrote it"
tr '\0' ' ' <"$mise_log" | grep -q "use -g --quiet uv" &&
  fail "writing the stub does not install uv"
pass "writing the Hermes stub provisions nothing"

# The desktop app owns Hermes, so our own stub must go rather than sit there
# answering `hermes` until the app's bootstrap replaces it.
printf '%s\n' "#!/bin/bash" "# $stub_marker" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 1 || true
[[ ! -e $test_home/.local/bin/hermes ]] ||
  fail "the desktop taking over removes the stub this command wrote"
pass "installing the desktop app removes the CLI stub"

# ...but the app's own hermes is not ours to delete.
printf '%s\n' "$app_stub_body" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 1 || true
[[ -x $test_home/.local/bin/hermes ]] ||
  fail "the desktop app's own hermes command survives"
pass "the app's own hermes command is left alone"

# A copy mise cannot vouch for is still a second Hermes.
printf '%s\n' "#!/bin/bash" "# $stub_marker" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
: >"$mise_log"
OMARCHY_TEST_MISE_WHERE_OK=1 run_installer 1 || true
tr '\0' '\n' <"$mise_log" | grep -q "uninstall" ||
  fail "takeover removes a mise copy even when it is not healthy"
pass "takeover removes an unhealthy mise copy"

# --check answers about Hermes being usable, not about the venv appearing. The
# venv exists from the python-deps stage, several stages before the command.
rm -rf "$test_home/.hermes"
rm -f "$test_home/.local/bin/hermes"
run_installer 1 --check && fail "--check reports Hermes missing before the app installs it"
mkdir -p "$test_home/.hermes/hermes-agent/venv/bin"
printf '%s\n' "#!/bin/bash" >"$test_home/.hermes/hermes-agent/venv/bin/hermes"
chmod +x "$test_home/.hermes/hermes-agent/venv/bin/hermes"
run_installer 1 --check && fail "--check waits for the install to finish, not just the venv"
touch "$test_home/.hermes/hermes-agent/.hermes-bootstrap-complete"
printf '%s\n' "#!/bin/bash" "exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\"" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 1 --check || fail "--check reports Hermes present once the app has finished"
pass "--check follows the app's completed install"

# An executable called hermes that belongs to something else is not this
# install being ready.
printf '%s\n' "#!/bin/bash" "exec /usr/local/bin/somebody-elses-hermes \"\$@\"" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 1 --check && fail "--check rejects a hermes command belonging to something else"
pass "--check rejects a foreign hermes command"
