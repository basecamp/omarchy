#!/bin/bash

set -euo pipefail

if (( $# != 1 )); then
  echo "usage: $0 BUILD_DIRECTORY" >&2
  exit 2
fi

build_directory=$1
if [[ ! -f $build_directory/CTestTestfile.cmake ]]; then
  echo "security campaign: not a configured plugin-runtime build: $build_directory" >&2
  exit 2
fi

campaign='^(plugin-manifest-v2-contract|plugin-wire-contract|plugin-permission-contract|plugin-sandbox-enforcement|capability-definition-contract|plugin-broker-core|plugin-sidecar-supervisor|plugin-sidecar-real-bwrap|plugin-worker-runtime|plugin-worker-channel|plugin-qml-broker-api|plugin-trusted-bridge|plugin-render-session|plugin-providers|plugin-revision-store|plugin-grant-store|plugin-audit-store|plugin-broker-runtime|plugin-channel-integration-bwrap|plugin-adversarial-harness|plugin-brokered-action-bwrap|plugin-malicious-peer|plugin-launcher-malicious-peer|plugin-launcher-bwrap|plugin-exhaustion-proof)$'

ctest --test-dir "$build_directory" --output-on-failure -R "$campaign"
