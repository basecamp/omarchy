#!/bin/bash

set -euo pipefail

root_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT

cmake -S "$root_dir" -B "$build_dir" -DCMAKE_BUILD_TYPE=Debug
cmake --build "$build_dir"

output=$("$build_dir/plugin-envelope-spike")
[[ $output == *"golden_header=40"* ]]
[[ $output == *"negotiation=three-role-v1"* ]]
[[ $output == *"generation=validated"* ]]
[[ $output == *"cancellation=correlated"* ]]
[[ $output == *"typed_error=recoverable"* ]]
[[ $output == *"fatal_cases=denied"* ]]
[[ $output == *"descriptor_policy=denied-or-typed"* ]]
[[ $output == *"identity=bound"* ]]

ctest --test-dir "$build_dir" --output-on-failure

printf '%s\n' "$output"
echo "envelope spike: PASS"
