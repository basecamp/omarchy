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

stub_marker="# Written by omarchy-install-hermes-cli."
app_stub_body='#!/bin/bash
exec /home/x/.hermes/hermes-agent/venv/bin/hermes "$@"'

# Writing the stub must not provision anything: user setup calls this on every
# machine, including the ones that never run Hermes.
: >"$mise_log"
rm -f "$test_home/.local/bin/hermes"
run_installer 0 || fail "installer failed with no desktop installed"
[[ -x $test_home/.local/bin/hermes ]] || fail "installer writes a hermes stub when the desktop is absent"
grep -qxF "$stub_marker" "$test_home/.local/bin/hermes" || fail "the stub records which command wrote it"
tr '\0' ' ' <"$mise_log" | grep -q "use -g --quiet uv" &&
  fail "writing the stub does not install uv"
pass "writing the Hermes stub provisions nothing"

# The desktop app owns Hermes, so our own stub must go rather than sit there
# answering `hermes` until the app's bootstrap replaces it.
printf '%s\n' "#!/bin/bash" "$stub_marker" >"$test_home/.local/bin/hermes"
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
printf '%s\n' "#!/bin/bash" "$stub_marker" >"$test_home/.local/bin/hermes"
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

# A hermes the user installed themselves -- the official installer, a wrapper of
# their own -- is not ours to replace. --check follows whether it runs, and
# installing steps aside so the default agent uses it.
official_body="#!/bin/bash
unset PYTHONPATH
unset PYTHONHOME
exec $test_home/.hermes/hermes-agent/venv/bin/hermes \"\$@\""
printf '%s\n' "$official_body" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 0 --check || fail "--check accepts a working foreign hermes command"
run_installer 0 || fail "installing over a foreign hermes command returns success"
run_installer 0 --now || fail "--now over a foreign hermes command returns success"
[[ $(cat "$test_home/.local/bin/hermes") == "$official_body" ]] ||
  fail "a foreign hermes command is left untouched"
pass "a foreign hermes command is preserved and satisfies --check"

# Broken foreign paths are still foreign. They cannot be used, so --check says
# so and the installer refuses rather than replacing them.
printf '%s\n' "$official_body" >"$test_home/.local/bin/hermes"
chmod -x "$test_home/.local/bin/hermes"
run_installer 0 --check && fail "--check rejects a non-executable foreign hermes"
run_installer 0 && fail "the installer does not succeed over a non-executable foreign hermes"
[[ -f $test_home/.local/bin/hermes && ! -x $test_home/.local/bin/hermes ]] ||
  fail "a non-executable foreign hermes is left untouched"
pass "a non-executable foreign hermes is preserved"

foreign_target="$test_home/foreign/hermes"
mkdir -p "$(dirname "$foreign_target")"
printf '%s\n' "$official_body" >"$foreign_target"
chmod +x "$foreign_target"
rm -f "$test_home/.local/bin/hermes"
ln -s "$foreign_target" "$test_home/.local/bin/hermes"
run_installer 0 --check || fail "--check accepts a foreign link to a working hermes command"
run_installer 0 || fail "the installer succeeds over a foreign link to a working hermes command"
run_installer 0 --now || fail "--now succeeds over a foreign link to a working hermes command"
[[ -L $test_home/.local/bin/hermes && $(readlink "$test_home/.local/bin/hermes") == "$foreign_target" ]] ||
  fail "a foreign link to a working hermes command is left untouched"
pass "a foreign link to a working hermes command is preserved"

rm -f "$test_home/.local/bin/hermes"
ln -s "$test_home/nowhere/hermes" "$test_home/.local/bin/hermes"
run_installer 0 --check && fail "--check rejects a dangling hermes link"
run_installer 0 && fail "the installer does not succeed over a dangling hermes link"
[[ -L $test_home/.local/bin/hermes && $(readlink "$test_home/.local/bin/hermes") == "$test_home/nowhere/hermes" ]] ||
  fail "a dangling hermes link is left untouched"
pass "a dangling hermes link is preserved"

# A directory passes -x on search permission alone. It is still not a command.
rm -f "$test_home/.local/bin/hermes"
mkdir "$test_home/.local/bin/hermes"
run_installer 0 --check && fail "--check rejects a directory at the hermes path"
run_installer 0 && fail "the installer does not succeed over a directory at the hermes path"
[[ -d $test_home/.local/bin/hermes ]] || fail "a directory at the hermes path is left untouched"
pass "a directory at the hermes path is preserved and rejected"

# Mentioning the installer is not the same as being written by it.
rmdir "$test_home/.local/bin/hermes"
mentions_body='#!/bin/bash
# Replaces the stub omarchy-install-hermes-cli used to write.
exec /usr/local/bin/hermes "$@"'
printf '%s\n' "$mentions_body" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 0 || fail "installing over a wrapper that mentions the installer returns success"
[[ $(cat "$test_home/.local/bin/hermes") == "$mentions_body" ]] ||
  fail "a wrapper that merely mentions the installer is left untouched"
pass "ownership needs the exact marker line, not a mention"

# Our own stub is ours to rewrite, so reinstalling refreshes it to the current
# template.
rm -f "$test_home/.local/bin/hermes"
printf '%s\n' "#!/bin/bash" "$stub_marker" "# stale template" >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
run_installer 0 || fail "reinstalling over our own stub succeeds"
grep -qxF "$stub_marker" "$test_home/.local/bin/hermes" || fail "the refreshed stub still carries the marker"
grep -q "stale template" "$test_home/.local/bin/hermes" && fail "reinstalling rewrites our own stub"
grep -q "exec mise x" "$test_home/.local/bin/hermes" || fail "the refreshed stub is the current template"
pass "reinstalling refreshes the Omarchy stub"
