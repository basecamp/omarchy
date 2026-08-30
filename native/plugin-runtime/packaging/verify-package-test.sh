#!/bin/bash

set -euo pipefail

if (( $# != 2 )); then
  echo "Usage: $0 <staging-root> <runtime-version>" >&2
  exit 64
fi

source_root=$1
version=$2
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
verifier=$script_dir/verify-package.sh
scratch=$(mktemp -d)
cleanup() {
  rm -rf -- "$scratch"
}
trap cleanup EXIT

expect_failure() {
  local description=$1 expected=$2
  shift 2
  if "$@" >"$scratch/output" 2>&1; then
    echo "negative package test unexpectedly passed: $description" >&2
    exit 1
  fi
  grep -F "$expected" "$scratch/output" >/dev/null || {
    echo "negative package test failed for the wrong reason: $description" >&2
    cat "$scratch/output" >&2
    exit 1
  }
}

reset_fixture() {
  rm -rf -- "$scratch/root"
  cp -a "$source_root" "$scratch/root"
}

"$verifier" --staging "$source_root" "$version" >/dev/null

reset_fixture
root=$scratch/root/usr/lib/omarchy/plugin-security/$version
touch "$root/shell/unexpected.qml"
expect_failure "unexpected file" "installed file manifest differs" "$verifier" --staging "$scratch/root" "$version"

reset_fixture
root=$scratch/root/usr/lib/omarchy/plugin-security/$version
chmod 775 "$root/shell"
expect_failure "writable directory" "runtime directory mode is not 755" "$verifier" --staging "$scratch/root" "$version"

reset_fixture
root=$scratch/root/usr/lib/omarchy/plugin-security/$version
mv "$root/policy/builtin-capabilities-v1.json" "$scratch/policy.json"
ln -s "$scratch/policy.json" "$root/policy/builtin-capabilities-v1.json"
expect_failure "policy symlink" "installed file manifest differs" "$verifier" --staging "$scratch/root" "$version"

reset_fixture
mkdir -p "$scratch/root/usr/bin"
touch "$scratch/root/usr/bin/omarchy-plugin-qml-worker"
expect_failure "global command" "package writes outside its owned versioned root" "$verifier" --staging "$scratch/root" "$version"

reset_fixture
root=$scratch/root/usr/lib/omarchy/plugin-security/$version
cp -a "$root" "$scratch/root/usr/lib/omarchy/plugin-security/9.9.9"
expect_failure "multiple versions" "staging package contains another runtime version" "$verifier" --staging "$scratch/root" "$version"

reset_fixture
root=$scratch/root/usr/lib/omarchy/plugin-security/$version
sed -i 's/^qt6-base=.*/qt6-base=0.0.0-0/' "$root/metadata/runtime-dependencies-v1.txt"
expect_failure "different Qt private ABI build" "runtime dependency contract differs from the required Arch package set or qt6-base build" "$verifier" --staging "$scratch/root" "$version"

echo "secure plugin package verifier negative tests passed"
