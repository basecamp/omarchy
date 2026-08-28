#!/bin/bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
build_dir=${1:-/tmp/omarchy-plugin-f1}
iterations=${F1_STRESS_ITERATIONS:-25}

cmake -S "$script_dir" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE="${F1_BUILD_TYPE:-Debug}" -DBUILD_TESTING=ON -DPLUGIN_SECURITY_F1_SANITIZERS="${F1_SANITIZERS:-OFF}"
cmake --build "$build_dir" -j"${F1_BUILD_JOBS:-2}"

campaign='plugin-exhaustion-proof|plugin-adversarial-harness|plugin-headless-slice-fake|plugin-embedded-bar-slice|plugin-expressive-surface|plugin-brokered-action$|plugin-supervisor-health|plugin-channel-integration-fake|plugin-sandbox-policy|plugin-render-session|plugin-surface-host|plugin-broker-core|plugin-broker-runtime'
if [[ ${F1_SANITIZERS:-OFF} != "ON" ]]; then
  campaign+='|plugin-sandbox-enforcement'
fi
ctest --test-dir "$build_dir" --output-on-failure -R "$campaign"
ctest --test-dir "$build_dir" --output-on-failure --repeat "until-fail:$iterations" -R 'plugin-exhaustion-proof|plugin-supervisor-health|plugin-expressive-surface|plugin-brokered-action$'

if [[ ${F1_REAL_BWRAP:-0} == "1" ]]; then
  ctest --test-dir "$build_dir" --output-on-failure -R 'plugin-channel-integration-bwrap|plugin-headless-slice-bwrap|plugin-brokered-action-bwrap|plugin-adversarial-sandbox'
fi
