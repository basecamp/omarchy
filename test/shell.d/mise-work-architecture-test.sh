#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The ISO bundles one Node.js tarball, named for the architecture it was built
# for. install/user/mise-work.sh must find the arm64 one on Apple Silicon and
# the x64 one elsewhere, and refuse anything it cannot name.

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/packages"

cat >"$test_tmp/bin/uname" <<'STUB'
#!/bin/bash
printf '%s\n' "$TEST_UNAME"
STUB

cat >"$test_tmp/bin/mise" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$MISE_TEST_LOG"
STUB

chmod +x "$test_tmp/bin/uname" "$test_tmp/bin/mise"

run_mise_work() {
  local machine="$1" home="$2" log="$3"

  HOME="$home" \
    PATH="$test_tmp/bin:$PATH" \
    TEST_UNAME="$machine" \
    MISE_TEST_LOG="$log" \
    OMARCHY_SETUP_CONTEXT=iso-chroot \
    OMARCHY_NODE_PACKAGE_DIR="$test_tmp/packages" \
    bash -eE -c 'source "$1"' bash "$ROOT/install/user/mise-work.sh"
}

# $1 uname -m, $2 the Node.js archive architecture it maps to, $3 version.
run_arch_case() {
  local machine="$1" archive_arch="$2" version="$3"
  local home="$test_tmp/home-$machine" payload="$test_tmp/payload-$machine"
  local archive="$test_tmp/packages/node-v$version-linux-$archive_arch.tar.gz"
  local log="$test_tmp/mise-$machine.log"

  mkdir -p "$home" "$payload/node-v$version-linux-$archive_arch/bin"
  printf '%s\n' "$machine" >"$payload/node-v$version-linux-$archive_arch/bin/node-marker"
  tar -C "$payload" -czf "$archive" "node-v$version-linux-$archive_arch"

  run_mise_work "$machine" "$home" "$log" >/dev/null ||
    fail "$machine cannot install the bundled Node.js archive"

  grep -Fxq "$machine" "$home/.local/share/mise/installs/node/$version/bin/node-marker" ||
    fail "$machine installs the matching bundled Node.js archive"
  grep -Fxq "use -g node@$version" "$log" ||
    fail "$machine activates the matching bundled Node.js version"
  pass "$machine uses the $archive_arch Node.js bundle"
}

# Both archives are staged side by side, so each machine has to pick, not
# merely find, the right one.
run_arch_case aarch64 arm64 26.7.0
run_arch_case x86_64 x64 24.0.0

# An architecture without a Node.js name has no tarball to look for; fail
# before guessing rather than after a silent no-op.
mkdir -p "$test_tmp/home-riscv64"
if run_mise_work riscv64 "$test_tmp/home-riscv64" "$test_tmp/mise-riscv64.log" >/dev/null 2>"$test_tmp/err"; then
  fail "an architecture without a bundled Node.js archive is accepted"
fi
grep -Fq 'unsupported Node.js architecture: riscv64' "$test_tmp/err" ||
  fail "an unsupported architecture is not named in the error"
# mise trust runs before the check, so only the Node.js activation is telling.
grep -q 'use -g node' "$test_tmp/mise-riscv64.log" &&
  fail "a Node.js version is activated for an architecture without a bundled archive"
pass "an architecture without a Node.js bundle fails loudly"
