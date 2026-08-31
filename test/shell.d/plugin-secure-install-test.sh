#!/bin/bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/bin"
calls="$test_dir/calls"
touch "$calls"
printf 'archive' >"$test_dir/archive.tar"

cat >"$test_dir/bin/omarchy-shell" <<'STUB'
#!/bin/bash
printf '%s\t%s\t%s\n' "${1:-}" "${2:-}" "${3:-}" >>"$INSTALL_TEST_CALLS"
[[ $1 == "plugin-security" ]] || exit 2
case $2 in
  installArchive) printf '%s\n' install-11111111111111111111111111111111 ;;
  pollInstall) printf '%s\n' '{"operationId":"install-11111111111111111111111111111111","state":"succeeded","result":{"plugin":"org.example.secure"}}' ;;
  reviewInstall)
    if [[ ! -e ${INSTALL_TEST_REVIEW_READY} ]]; then
      touch "$INSTALL_TEST_REVIEW_READY"
      exit 0
    fi
    printf '%s\n' permission-22222222222222222222222222222222
    ;;
  *) exit 3 ;;
esac
STUB
cat >"$test_dir/bin/omarchy-plugin-permissions" <<'STUB'
#!/bin/bash
printf 'permissions\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >>"$INSTALL_TEST_CALLS"
STUB
chmod +x "$test_dir/bin/omarchy-shell" "$test_dir/bin/omarchy-plugin-permissions"

export PATH="$test_dir/bin:$PATH"
export INSTALL_TEST_CALLS="$calls"
export INSTALL_TEST_REVIEW_READY="$test_dir/review-ready"

rg -q '^# omarchy:alias=omarchy plugin install$' "$ROOT/bin/omarchy-plugin-add" ||
  fail "trusted v1 install alias remains unchanged"
rg -q '^# omarchy:args=<archive>$' "$ROOT/bin/omarchy-plugin-secure-install" ||
  fail "secure install publishes command metadata"
rg -q 'target: "plugin-security"' "$ROOT/native/plugin-runtime/shell/SecurePluginHost.qml" ||
  fail "secure install has a dedicated bounded shell IPC target"
! rg -q 'installer\.[A-Za-z]+\([^)]*(revision|digest)' "$ROOT/native/plugin-runtime/shell/SecurePluginHost.qml" ||
  fail "secure install QML does not carry exact revision authority"

output=$(script -qefc "'$ROOT/bin/omarchy-plugin-secure-install' '$test_dir/archive.tar'" /dev/null)
[[ $output == *"Staging sandboxed schema-v2 plugin"* &&
   $output == *"Activated sandboxed schema-v2 plugin: org.example.secure"* ]] ||
  fail "secure install clearly identifies its sandboxed v2 path" "$output"
grep -F $'plugin-security\tinstallArchive\t'"$(realpath "$test_dir/archive.tar")" "$calls" >/dev/null ||
  fail "secure install sends one canonical archive path"
[[ $(grep -c $'plugin-security\treviewInstall' "$calls") == 2 ]] ||
  fail "exact review remains retryable until the reconciled slot is ready"
grep -F $'permissions\treview\torg.example.secure\t--operation\tpermission-22222222222222222222222222222222' "$calls" >/dev/null ||
  fail "secure install reuses the exact native permission review"
pass "secure archive install stages, reconciles, and delegates exact review"

help=$("$ROOT/bin/omarchy-plugin-secure-install" --help)
[[ $help == *'plugin add'* && $help == *'trusted pre-security plugins'* ]] ||
  fail "secure install distinguishes the trusted v1 commands"

if "$ROOT/bin/omarchy-plugin-secure-install" "$test_dir/archive.tar" >/dev/null 2>&1; then
  fail "secure install accepted a non-interactive permission flow"
fi
if script -qefc "'$ROOT/bin/omarchy-plugin-secure-install' '$test_dir/missing.tar'" /dev/null >/dev/null 2>&1; then
  fail "secure install accepted a missing archive"
fi
ln -s "$test_dir/archive.tar" "$test_dir/archive-link.tar"
if script -qefc "'$ROOT/bin/omarchy-plugin-secure-install' '$test_dir/archive-link.tar'" /dev/null >/dev/null 2>&1; then
  : # CLI canonicalization is ergonomic; native O_NOFOLLOW sees the canonical target.
fi
pass "secure install rejects non-interactive and missing inputs"
