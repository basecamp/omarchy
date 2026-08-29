#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
calls="$test_tmp/calls"
migration="$ROOT/migrations/1787954420.sh"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-pkg-present" <<'SH'
#!/bin/bash
[[ " ${OMARCHY_TEST_INSTALLED_PACKAGES:-} " == *" $1 "* ]]
SH

cat >"$mock_bin/omarchy-pkg-aur-add" <<'SH'
#!/bin/bash
printf 'package:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH

cat >"$mock_bin/omafox" <<'SH'
#!/bin/bash
printf 'omafox:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo:%s\n' "$*" >>"$OMARCHY_TEST_CALLS"
SH

chmod +x "$mock_bin"/*

export PATH="$mock_bin:$PATH"
export OMARCHY_PATH="$ROOT"
export OMARCHY_TEST_CALLS="$calls"

jq -e '
  .policies.ExtensionSettings["@omafox"] == {
    "installation_mode": "normal_installed",
    "install_url": "https://addons.mozilla.org/firefox/downloads/latest/omafox/latest.xpi"
  }
' "$ROOT/default/firefox/policies.json" >/dev/null || fail "Firefox policy normally installs Omafox from AMO"
pass "Firefox policy normally installs Omafox from AMO"

run_migration() {
  : >"$calls"
  OMARCHY_TEST_INSTALLED_PACKAGES=$1 bash -euo pipefail "$migration" >/dev/null
}

run_migration ""
[[ ! -s $calls ]] || fail "Omafox migration skips systems without Firefox or Zen" "$(<"$calls")"
pass "Omafox migration skips systems without Firefox or Zen"

run_migration "firefox"
grep -Fxq 'package:omafox' "$calls" || fail "Omafox migration installs the package for Firefox"
grep -Fq '/usr/lib/firefox/distribution/policies.json' "$calls" || fail "Omafox migration installs the Firefox policy"
if grep -Fq '/opt/zen-browser/distribution/policies.json' "$calls"; then
  fail "Omafox migration does not install a Zen policy when Zen is absent"
fi
grep -Fxq 'omafox:setup' "$calls" || fail "Omafox migration configures the Firefox user"
pass "Omafox migration configures existing Firefox installs"

run_migration "zen-browser-bin"
grep -Fxq 'package:omafox' "$calls" || fail "Omafox migration installs the package for Zen"
grep -Fq '/opt/zen-browser/distribution/policies.json' "$calls" || fail "Omafox migration installs the Zen policy"
if grep -Fq '/usr/lib/firefox/distribution/policies.json' "$calls"; then
  fail "Omafox migration does not install a Firefox policy when Firefox is absent"
fi
grep -Fxq 'omafox:setup' "$calls" || fail "Omafox migration configures the Zen user"
pass "Omafox migration configures existing Zen installs"

run_migration "firefox zen-browser-bin"
[[ $(grep -Fxc 'package:omafox' "$calls") == 1 ]] || fail "Omafox migration installs the package once when both browsers exist"
grep -Fq '/usr/lib/firefox/distribution/policies.json' "$calls" || fail "Omafox migration refreshes the Firefox policy"
grep -Fq '/opt/zen-browser/distribution/policies.json' "$calls" || fail "Omafox migration refreshes the Zen policy"
[[ $(grep -Fxc 'omafox:setup' "$calls") == 1 ]] || fail "Omafox migration runs setup once when both browsers exist"
pass "Omafox migration configures both installed browsers in one pass"
