#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR="$ROOT/test/shell"

shopt -s nullglob
tests=()
for test in "$TEST_DIR"/*-test.sh; do
  [[ $(basename "$test") == "base-test.sh" ]] && continue
  tests+=("$test")
done
shopt -u nullglob

if (( ${#tests[@]} == 0 )); then
  echo "No shell tests found in $TEST_DIR" >&2
  exit 1
fi

for test in "${tests[@]}"; do
  printf '==> %s\n' "${test#$ROOT/}"
  bash "$test"
done
