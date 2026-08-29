#!/bin/bash

set -euo pipefail

if (( $# != 7 )); then
  echo "usage: $0 LAB BUILD_DIR HOST PERMISSION_STORE FIXTURES DYNAMIC_GRANT NETWORK_DEFINITION" >&2
  exit 2
fi

lab=$1
build_dir=$2
host=$3
permission_store=$4
fixtures=$5
dynamic_grant=$6
network_definition=$7
stage_parent=$(mktemp -d)

cleanup() {
  rm -rf -- "$stage_parent"
}
trap cleanup EXIT

stage=$($lab prepare "$build_dir" "$stage_parent" | tail -n 1)
$lab verify "$stage"

worker=$stage/usr/lib/omarchy/plugin-runtime/omarchy-plugin-qml-worker
[[ -x $worker ]] || {
  echo "staged production worker missing: $worker" >&2
  exit 1
}

OMARCHY_PLUGIN_E2E_ONLY_AUTHORIZED=1 \
  "$(dirname "$0")/product_e2e_test.sh" \
  "$host" "$worker" "$permission_store" "$fixtures" "$dynamic_grant" \
  "$network_definition"
