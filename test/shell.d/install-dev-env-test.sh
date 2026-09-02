#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# rustup's default download backend stalls on current Asahi kernels, so the
# Rust installer must run with RUSTUP_USE_CURL=1 on Apple Silicon and untouched
# everywhere else.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"

# The installer script "downloaded" by curl records the environment it ran in.
cat >"$test_tmp/bin/curl" <<'STUB'
#!/bin/bash
cat <<'INSTALLER'
printf '%s\n' "${RUSTUP_USE_CURL:-unset}" >"$OMARCHY_TEST_RUSTUP_ENV"
INSTALLER
STUB

cat >"$test_tmp/bin/omarchy-hw-apple-silicon" <<'STUB'
#!/bin/bash
[[ ${OMARCHY_TEST_APPLE_SILICON:-0} == 1 ]]
STUB

chmod +x "$test_tmp/bin"/*

export PATH="$test_tmp/bin:$PATH"
export OMARCHY_TEST_RUSTUP_ENV="$test_tmp/rustup-env"

OMARCHY_TEST_APPLE_SILICON=1 "$ROOT/bin/omarchy-install-dev-env" rust >/dev/null ||
  fail "installing Rust on Apple Silicon fails"
[[ $(<"$OMARCHY_TEST_RUSTUP_ENV") == 1 ]] ||
  fail "Rust does not use the curl backend on Apple Silicon"
pass "Rust uses the curl backend on Apple Silicon"

OMARCHY_TEST_APPLE_SILICON=0 "$ROOT/bin/omarchy-install-dev-env" rust >/dev/null ||
  fail "installing Rust on other hardware fails"
[[ $(<"$OMARCHY_TEST_RUSTUP_ENV") == unset ]] ||
  fail "Rust is forced onto the curl backend on other hardware"
pass "Rust keeps rustup's default backend on other hardware"
