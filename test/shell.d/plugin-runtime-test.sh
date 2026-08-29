#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

runtime_root="$ROOT/native/plugin-runtime"

for directory in worker bridge tests; do
  [[ -f $runtime_root/$directory/CMakeLists.txt ]] ||
    fail "plugin runtime is missing its $directory build boundary"
done
[[ -f $runtime_root/contracts/wire/CMakeLists.txt ]] ||
  fail "plugin runtime is missing its wire protocol build boundary"
[[ -f $runtime_root/shell/SecurePluginHost.qml ]] ||
  fail "plugin runtime is missing its Quickshell integration boundary"
pass "plugin runtime keeps native boundaries independently buildable"

grep -F 'contracts/${contract}/CMakeLists.txt' "$runtime_root/CMakeLists.txt" >/dev/null ||
  fail "contract owners must edit the shared root CMake file to land"
grep -F 'direct execution denied' "$runtime_root/worker/main.cpp" >/dev/null ||
  fail "worker skeleton does not fail closed before a trusted launcher exists"
grep -F 'return false;' "$runtime_root/bridge/PluginHostInfo.cpp" >/dev/null ||
  fail "bridge skeleton advertises plugin availability before a broker exists"
grep -F 'root_not_item' "$runtime_root/worker/worker_runtime_test.cpp" >/dev/null ||
  fail "worker does not reject plugin-created top-level windows"
pass "native runtime and offscreen worker remain fail-closed"

grep -F 'OMARCHY_PLUGIN_V2_ENABLED' "$ROOT/shell/shell.qml" >/dev/null ||
  fail "existing shell lacks the explicit schema-v2 feature gate"
grep -F 'OMARCHY_PLUGIN_V2_SHELL_ENTRY' "$ROOT/shell/shell.qml" >/dev/null ||
  fail "existing shell cannot load a side-by-side v2 integration entry"
grep -F 'legacy-unsandboxed-v1' "$ROOT/shell/services/PluginRegistry.qml" >/dev/null ||
  fail "schema-v1 plugins are not explicitly labeled legacy and unsandboxed"
grep -F 'will not fall back to legacy QML loading' "$ROOT/shell/services/PluginRegistry.qml" >/dev/null ||
  fail "rejected schema-v2 manifests can fall through ambiguously"
grep -F 'PanelWindow {' "$runtime_root/shell/SecurePanelSurface.qml" >/dev/null ||
  fail "secure panels are not owned by the Quickshell layer host"
grep -F 'mask: Region { item: remote }' "$runtime_root/shell/SecureOverlaySurface.qml" >/dev/null ||
  fail "secure overlays lack a shell-owned bounded input mask"
grep -F 'result.push({ id: declaration.surfaceKey' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure bar surfaces are not exposed as transient existing-bar items"
pass "schema-v2 integrates through dormant shell-owned surfaces without v1 fallback"

[[ ! -e $runtime_root/host ]] ||
  fail "standalone ordinary-window host remains in the product graph"

[[ ! -e $ROOT/bin/omarchy-plugin-permission ]] ||
  fail "reference permission inspector is exposed through the end-user router"
[[ ! -e $ROOT/bin/omarchy-plugin-audit ]] ||
  fail "reference audit inspector is exposed through the end-user router"
[[ ! -e $ROOT/migrations/1787937949.sh ]] ||
  fail "an installed migration activates the reference plugin host"
activation_references=$(grep -RFl 'omarchy-plugin-host.service' "$ROOT/install" "$ROOT/migrations" || true)
[[ -z $activation_references ]] ||
  fail "installed setup activates the reference plugin host" "$activation_references"
pass "secure runtime has no default activation path or standalone product host"
