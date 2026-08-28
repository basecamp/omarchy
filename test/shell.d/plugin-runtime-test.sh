#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

runtime_root="$ROOT/native/plugin-runtime"

for directory in protocol-version host worker bridge tests; do
  [[ -f $runtime_root/$directory/CMakeLists.txt ]] ||
    fail "plugin runtime is missing its $directory build boundary"
done
pass "plugin runtime keeps native boundaries independently buildable"

grep -F 'contracts/${contract}/CMakeLists.txt' "$runtime_root/CMakeLists.txt" >/dev/null ||
  fail "contract owners must edit the shared root CMake file to land"
grep -F 'direct execution denied' "$runtime_root/worker/main.cpp" >/dev/null ||
  fail "worker skeleton does not fail closed before a trusted launcher exists"
grep -F 'return false;' "$runtime_root/bridge/PluginHostInfo.cpp" >/dev/null ||
  fail "bridge skeleton advertises plugin availability before a broker exists"
pass "native runtime skeleton remains fail-closed"

[[ ! -e $ROOT/bin/omarchy-plugin-permission ]] ||
  fail "reference permission inspector is exposed through the end-user router"
[[ ! -e $ROOT/bin/omarchy-plugin-audit ]] ||
  fail "reference audit inspector is exposed through the end-user router"
[[ ! -e $ROOT/migrations/1787937949.sh ]] ||
  fail "an installed migration activates the reference plugin host"
activation_references=$(grep -RFl 'omarchy-plugin-host.service' "$ROOT/install" "$ROOT/migrations" || true)
[[ -z $activation_references ]] ||
  fail "installed setup activates the reference plugin host" "$activation_references"
pass "reference runtime has no end-user command or service activation path"
