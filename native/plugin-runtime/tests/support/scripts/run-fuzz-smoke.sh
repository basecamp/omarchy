#!/bin/bash

set -euo pipefail

support_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runtime_dir=$(cd -- "$support_dir/../.." && pwd)
build_dir=${PLUGIN_SECURITY_FUZZ_BUILD_DIR:-$runtime_dir/../../build/plugin-runtime-b6-fuzz}
corpus_dir="$build_dir/corpus"

hex_to_binary() {
  local input=$1
  local output=$2
  local hex pair
  hex=$(tr -d '[:space:]' <"$input")
  if (( ${#hex} % 2 != 0 )); then
    echo "Odd-length hexadecimal fixture: $input" >&2
    return 1
  fi
  : >"$output"
  while [[ -n $hex ]]; do
    pair=${hex:0:2}
    printf '%b' "\\x$pair" >>"$output"
    hex=${hex:2}
  done
}

cmake -S "$runtime_dir" -B "$build_dir" -G Ninja \
  -DBUILD_TESTING=ON \
  -DPLUGIN_SECURITY_BUILD_FUZZERS=ON \
  -DOMARCHY_BUILD_PERMISSIONS_CONTRACT=OFF \
  -DOMARCHY_BUILD_SANDBOX_CONTRACT=OFF \
  -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_CXX_FLAGS="-fsanitize=fuzzer-no-link,address,undefined -fno-omit-frame-pointer"
cmake --build "$build_dir" --target plugin-security-fuzzers

mkdir -p "$corpus_dir/envelope" "$corpus_dir/manifest" "$corpus_dir/render"
hex_to_binary "$support_dir/../fixtures/wire/v1/hello-control.hex" \
  "$corpus_dir/envelope/hello-control"
cp "$runtime_dir/contracts/manifest/fixtures/valid-minimal/manifest.json" \
  "$corpus_dir/manifest/valid-minimal.json"
hex_to_binary "$support_dir/../fixtures/wire/v1/welcome-control.hex" \
  "$corpus_dir/render/arbitrary-seed"

export ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=1:halt_on_error=1}
export UBSAN_OPTIONS=${UBSAN_OPTIONS:-halt_on_error=1:print_stacktrace=1}
timeout 30s "$build_dir/tests/support/omarchy-plugin-envelope-fuzzer" \
  -runs=512 -seed=8102026 -max_len=70000 "$corpus_dir/envelope"
timeout 30s "$build_dir/tests/support/omarchy-plugin-manifest-fuzzer" \
  -runs=512 -seed=8102026 -max_len=262144 "$corpus_dir/manifest"
timeout 30s "$build_dir/tests/support/omarchy-plugin-render-fuzzer" \
  -runs=512 -seed=8102026 -max_len=256 "$corpus_dir/render"
