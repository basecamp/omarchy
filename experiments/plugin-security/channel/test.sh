#!/bin/bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

cmake -S "$root_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Debug
cmake --build "$build_dir"

output=$("$build_dir/plugin-channel-spike" "trusted.clock" "forged.admin")
[[ $output == *"authorized_as=trusted.clock"* ]]
[[ $output == *"plugin_id=forged.admin"* ]]
[[ $output != *"authorized_as=forged.admin"* ]]

ctest --test-dir "$build_dir" --output-on-failure

echo "channel spike: PASS"
