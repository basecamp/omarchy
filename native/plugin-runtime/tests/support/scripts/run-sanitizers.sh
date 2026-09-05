#!/bin/bash

set -euo pipefail

support_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime_dir=$(cd -- "$support_dir/../.." && pwd)
build_dir=${PLUGIN_SECURITY_SANITIZER_BUILD_DIR:-$runtime_dir/../../build/plugin-runtime-b6-sanitized}

cmake -S "$runtime_dir" -B "$build_dir" -G Ninja \
  -DBUILD_TESTING=ON \
  -DOMARCHY_BUILD_PERMISSIONS_CONTRACT=OFF \
  -DOMARCHY_BUILD_SANDBOX_CONTRACT=OFF \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" \
  -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build "$build_dir" --target \
  omarchy-plugin-support-test \
  omarchy-plugin-malicious-peer-test

ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1} \
UBSAN_OPTIONS=${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1} \
  ctest --test-dir "$build_dir" --output-on-failure \
    --tests-regex '^plugin-(test-support|malicious-peer)$'
