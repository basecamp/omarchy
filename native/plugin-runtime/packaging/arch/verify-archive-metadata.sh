#!/bin/bash

set -euo pipefail

usage() {
  echo "Usage: $0 <package-archive> <runtime-version>" >&2
  exit 64
}

fail() {
  echo "secure plugin archive metadata verification failed: $1" >&2
  exit 1
}

if (( $# != 2 )); then
  usage
fi

archive=$(realpath -e -- "$1")
version=$2
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  fail "runtime version is not numeric semver"

pkginfo=$(bsdtar -xOf "$archive" .PKGINFO)
grep -Fx "pkgname = omarchy-plugin-security" <<<"$pkginfo" >/dev/null ||
  fail "archive package name is not canonical"
grep -Fx "pkgver = ${version}-1" <<<"$pkginfo" >/dev/null ||
  fail "archive package version is not canonical"
grep -Fx "arch = x86_64" <<<"$pkginfo" >/dev/null ||
  fail "archive architecture is not x86_64"

contract_path=usr/lib/omarchy/plugin-security/$version/metadata/runtime-dependencies-v1.txt
contract=$(bsdtar -xOf "$archive" "$contract_path")
expected_contract=$(cat <<'EOF'
bubblewrap
curl
glibc
libgcc
libseccomp
libstdc++
mpv
omarchy
qt6-base
qt6-declarative
quickshell
systemd-libs
EOF
)
[[ $contract == "$expected_contract" ]] ||
  fail "archive runtime contract differs from the required Arch package set"
archive_dependencies=$(sed -n 's/^depend = //p' <<<"$pkginfo" | LC_ALL=C sort)
contract_dependencies=$(LC_ALL=C sort <<<"$contract")
[[ $archive_dependencies == "$contract_dependencies" ]] ||
  fail "archive dependencies differ from the configured runtime contract"

echo "secure plugin archive metadata verification passed: $archive"
