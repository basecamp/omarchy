#!/bin/bash

set -euo pipefail

helper=$1
build_dir=$2
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

stage=$("$helper" prepare "$build_dir" "$test_root")
"$helper" verify "$stage" >/dev/null

worker_digest=$(sed -n 's/^worker_sha256=//p' "$stage/PROVENANCE")
bundle_digest=$(basename "$stage")
[[ $worker_digest =~ ^[0-9a-f]{64}$ && $bundle_digest =~ ^[0-9a-f]{64}$ &&
   $worker_digest != "$bundle_digest" ]] || {
  echo "Worker and bundle identities were not kept separate" >&2
  exit 1
}

printf '\n' >>"$stage/usr/bin/omarchy-plugin-host"
if "$helper" verify "$stage" >/dev/null 2>&1; then
  echo "Changed host artifact retained trusted bundle identity" >&2
  exit 1
fi
