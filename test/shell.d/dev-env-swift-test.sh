#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin" "$test_tmp/home"

cat >"$test_tmp/bin/omarchy-pkg-aur-add" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PACKAGE_CALLS"
[[ ${FAIL_PACKAGE_CALL:-0} != "1" ]]
STUB
cat >"$test_tmp/bin/omarchy-pkg-drop" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$PACKAGE_CALLS"
[[ ${FAIL_PACKAGE_CALL:-0} != "1" ]]
STUB
chmod +x "$test_tmp/bin/omarchy-pkg-aur-add" "$test_tmp/bin/omarchy-pkg-drop"

export HOME="$test_tmp/home"
export PACKAGE_CALLS="$test_tmp/package-calls"
export PATH="$test_tmp/bin:$PATH"

"$ROOT/bin/omarchy-install-dev-env" swift >/dev/null
[[ $(<"$PACKAGE_CALLS") == "swift-bin" ]] || fail "Swift installer selects the Arch-compatible binary package"
pass "Swift installer selects the Arch-compatible binary package"

: >"$PACKAGE_CALLS"
"$ROOT/bin/omarchy-remove-dev-env" swift >/dev/null
[[ $(<"$PACKAGE_CALLS") == "swift-bin" ]] || fail "Swift remover drops the package installed by Omarchy"
pass "Swift remover drops the package installed by Omarchy"

if FAIL_PACKAGE_CALL=1 "$ROOT/bin/omarchy-install-dev-env" swift >/dev/null; then
  fail "Swift installer propagates package installation failure"
fi
pass "Swift installer propagates package installation failure"

if FAIL_PACKAGE_CALL=1 "$ROOT/bin/omarchy-remove-dev-env" swift >/dev/null; then
  fail "Swift remover propagates package removal failure"
fi
pass "Swift remover propagates package removal failure"

base_packages="$ROOT/install/omarchy-base.packages"
for package in libxml2-legacy patchelf; do
  grep -qx "$package" "$base_packages" || fail "Swift dependency is installed on pristine offline systems: $package"
done
pass "Swift dependencies are installed on pristine offline systems"
