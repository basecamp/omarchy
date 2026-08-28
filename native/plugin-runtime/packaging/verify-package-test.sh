#!/bin/bash

set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: $0 <known-good-omarchy-package.pkg.tar.zst>" >&2
  exit 64
fi

archive=$1
[[ -f $archive ]] || { echo "Package not found: $archive" >&2; exit 66; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
verifier=$script_dir/verify-package.sh
fixture=$script_dir/tests/elf_fixture.c
scratch=$(mktemp -d)
staging=$scratch/root
mkdir -p "$staging"
cleanup() {
  rm -rf -- "$scratch"
}
trap cleanup EXIT

bsdtar -xf "$archive" -C "$staging"

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

"$verifier" --staging "$staging" >/dev/null

runtime=$staging/usr/lib/omarchy/plugin-runtime
module=$staging/usr/lib/qt6/qml/Omarchy/PluginHost
host=$staging/usr/bin/omarchy-plugin-host
permission_store=$staging/usr/bin/omarchy-plugin-permission-store
qmltypes=$module/omarchy-plugin-host-bridge.qmltypes

touch "$runtime/fake-test-helper"
expect_failure "private helper" "private worker directory contains" \
  "$verifier" --staging "$staging"
rm "$runtime/fake-test-helper"

touch "$module/unexpected.qml"
expect_failure "unexpected QML file" "QML plugin directory contains" \
  "$verifier" --staging "$staging"
rm "$module/unexpected.qml"

mv "$qmltypes" "$scratch/qmltypes"
ln -s qmldir "$qmltypes"
expect_failure "QML metadata symlink" "QML type description is absent or linked" \
  "$verifier" --staging "$staging"
rm "$qmltypes"
mv "$scratch/qmltypes" "$qmltypes"

chmod 4755 "$host"
expect_failure "setuid host" "trusted host mode is not 755" \
  "$verifier" --staging "$staging"
chmod 755 "$host"

chmod 775 "$runtime"
expect_failure "group-writable runtime" "runtime directory mode is not 755" \
  "$verifier" --staging "$staging"
chmod 755 "$runtime"

cp "$permission_store" "$scratch/permission-store"

gcc -fPIE -pie -Wl,-z,relro -Wl,-rpath,/tmp "$fixture" -o "$permission_store"
expect_failure "RPATH" "contains an RPATH or RUNPATH" \
  "$verifier" --staging "$staging"

gcc -no-pie "$fixture" -o "$permission_store"
expect_failure "non-PIE executable" "is not an x86-64 PIE executable" \
  "$verifier" --staging "$staging"

gcc -fPIE -pie -Wl,-z,execstack "$fixture" -o "$permission_store"
expect_failure "executable stack" "has no non-executable GNU stack declaration" \
  "$verifier" --staging "$staging"

gcc -fPIE -pie -Wl,-z,norelro "$fixture" -o "$permission_store"
expect_failure "missing RELRO" "has no GNU RELRO segment" \
  "$verifier" --staging "$staging"

cp "$host" "$permission_store"
expect_failure "unexpected dependency" "has unexpected DT_NEEDED libQt6Core.so.6" \
  "$verifier" --staging "$staging"

cp "$scratch/permission-store" "$permission_store"
mkdir "$scratch/fake-ldd"
cp "$script_dir/tests/fake-unresolved-ldd" "$scratch/fake-ldd/ldd"
chmod 755 "$scratch/fake-ldd/ldd"
expect_failure "unresolved dependency" "has an unresolved runtime dependency" \
  env PATH="$scratch/fake-ldd:$PATH" "$verifier" --staging "$staging"

mkdir "$scratch/fake-owner"
cp "$script_dir/tests/fake-owner-bsdtar" "$scratch/fake-owner/bsdtar"
chmod 755 "$scratch/fake-owner/bsdtar"
real_bsdtar=$(type -P bsdtar)
expect_failure "non-root archive owner" "archive member is not owned by root:root" \
  env PATH="$scratch/fake-owner:$PATH" REAL_BSDTAR="$real_bsdtar" \
  "$verifier" "$archive"

echo "plugin package verifier negative tests passed"
