#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

xcompose_install="$ROOT/install/user/xcompose.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

home="$test_dir/home"
mkdir -p "$home"

OMARCHY_USER_NAME="Example User" \
OMARCHY_USER_EMAIL="user@example.com" \
HOME="$home" \
  bash -eE "$xcompose_install"

grep -qFx '<Multi_key> <space> <n> : "Example User"' "$home/.XCompose" ||
  fail "XCompose install writes the user's name"
grep -qFx '<Multi_key> <space> <e> : "user@example.com"' "$home/.XCompose" ||
  fail "XCompose install writes the user's email"
pass "XCompose install creates the default file with the user's identity"

printf '\n<Multi_key> <space> <x> : "custom"\n' >>"$home/.XCompose"
before=$(sha256sum "$home/.XCompose")

HOME="$home" bash -euo pipefail "$xcompose_install"

[[ $(sha256sum "$home/.XCompose") == "$before" ]] ||
  fail "XCompose install preserves an existing user file" "$(cat "$home/.XCompose")"
pass "XCompose install preserves user customizations on rerun"
