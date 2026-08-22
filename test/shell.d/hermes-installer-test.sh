#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
curl_log="$test_tmp/curl"
installer_log="$test_tmp/installer"
mkdir -p "$mock_bin" "$test_home/.local/bin"

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_CURL_LOG"
[[ ${OMARCHY_TEST_CURL_FAIL:-false} != "true" ]] || exit 22
while (($#)); do
  if [[ $1 == "-o" ]]; then
    cp "$OMARCHY_TEST_INSTALLER" "$2"
    exit 0
  fi
  shift
done
exit 2
SH

cat >"$test_tmp/installer" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_INSTALLER_LOG"
mkdir -p "$HOME/.hermes/hermes-agent/.git"
[[ ${OMARCHY_TEST_INSTALLER_FAIL:-false} != "true" ]] || exit 1
printf '#!/bin/bash\n' >"$HOME/.local/bin/hermes"
chmod +x "$HOME/.local/bin/hermes"
SH

chmod +x "$mock_bin/curl" "$test_tmp/installer"

export HOME="$test_home"
export PATH="$test_home/.local/bin:$mock_bin:$ROOT/bin:/usr/bin"
export OMARCHY_TEST_CURL_LOG="$curl_log"
export OMARCHY_TEST_INSTALLER_LOG="$installer_log"
export OMARCHY_TEST_INSTALLER="$test_tmp/installer"

printf '#!/bin/bash\nprintf real-hermes\n' >"$test_home/.local/bin/hermes"
chmod +x "$test_home/.local/bin/hermes"
PATH="$mock_bin:$ROOT/bin:/usr/bin" omarchy-install-hermes-cli --stub
grep -Fxq 'printf real-hermes' "$test_home/.local/bin/hermes" ||
  fail "Hermes stub setup preserves an exact-path real launcher outside PATH"
pass "Hermes stub setup preserves an exact-path real launcher outside PATH"

rm "$test_home/.local/bin/hermes"
ln -s "$test_home/.hermes/missing-hermes" "$test_home/.local/bin/hermes"
omarchy-install-hermes-cli --stub
grep -Fxq '# omarchy-hermes-installer-stub' "$test_home/.local/bin/hermes" ||
  fail "Hermes preinstall is a supported-installer lazy stub"
pass "Hermes preinstall creates a supported-installer lazy stub"

printf '# stale marked stub\n' >>"$test_home/.local/bin/hermes"
omarchy-install-hermes-cli --stub
if grep -Fxq '# stale marked stub' "$test_home/.local/bin/hermes"; then
  fail "Hermes stub setup replaces a marked Omarchy stub"
fi
pass "Hermes stub setup replaces a marked Omarchy stub"

"$test_home/.local/bin/hermes" --version
mapfile -d '' -t installer_args <"$installer_log"
[[ ${installer_args[*]} == "--skip-setup --non-interactive" ]] ||
  fail "Hermes lazy stub invokes the official installer noninteractively" "${installer_args[*]}"
mapfile -d '' -t curl_args <"$curl_log"
[[ ${curl_args[*]} == "-fsSL https://hermes-agent.nousresearch.com/install.sh -o "* ]] ||
  fail "Hermes installer downloads the Tier-1 installer to a file" "${curl_args[*]}"
pass "Hermes lazy stub invokes the Tier-1 installer with noninteractive setup skipped"

: >"$curl_log"
omarchy-install-hermes-cli
[[ ! -s $curl_log ]] || fail "Hermes installer rerun leaves an installed Hermes to its self-updater"
pass "Hermes installer rerun leaves updates to hermes update"

rm "$test_home/.local/bin/hermes"
: >"$curl_log"
if OMARCHY_TEST_CURL_FAIL=true omarchy-install-hermes-cli >"$test_tmp/download-failure" 2>&1; then
  fail "Hermes installer reports download failure"
fi
[[ ! -e $test_home/.local/bin/hermes ]] || fail "download failure creates no Hermes command"
pass "Hermes installer fails cleanly when the official script cannot be downloaded"

: >"$curl_log"
if OMARCHY_TEST_INSTALLER_FAIL=true omarchy-install-hermes-cli >"$test_tmp/install-failure" 2>&1; then
  fail "Hermes installer reports official installer failure"
fi
[[ -d $test_home/.hermes/hermes-agent/.git ]] || fail "failed installer preserves upstream partial state for its recovery path"
[[ ! -e $test_home/.local/bin/hermes ]] || fail "failed installer exposes no broken Hermes command"
pass "Hermes installer preserves partial state but exposes no broken command"

cat >"$test_tmp/installer" <<'SH'
#!/bin/bash
exit 0
SH
if omarchy-install-hermes-cli >"$test_tmp/missing-command" 2>&1; then
  fail "Hermes installer verifies the public command after upstream success"
fi
pass "Hermes installer rejects success without an installed command"
