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

ctest --test-dir "$build_directory" --output-on-failure -L security
