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
grep -F 'direct execution denied' "$runtime_root/worker/src/main.cpp" >/dev/null ||
  fail "worker skeleton does not fail closed before a trusted launcher exists"
grep -F 'root_not_item' "$runtime_root/worker/tests/worker_runtime_test.cpp" >/dev/null ||
  fail "worker does not reject plugin-created top-level windows"
pass "native runtime and offscreen worker remain fail-closed"

grep -F 'OMARCHY_PLUGIN_V2_ENABLED' "$ROOT/shell/shell.qml" >/dev/null ||
  fail "existing shell lacks the explicit schema-v2 feature gate"
grep -F 'OMARCHY_PLUGIN_V2_SHELL_ENTRY' "$ROOT/shell/shell.qml" >/dev/null ||
  fail "existing shell cannot load a side-by-side v2 integration entry"
grep -F 'pre-security-trusted-by-default-v1' "$ROOT/shell/services/PluginRegistry.qml" >/dev/null ||
  fail "schema-v1 plugins are not explicitly labeled pre-security and trusted by default"
grep -F 'will not fall back to pre-security QML loading' "$ROOT/shell/services/PluginRegistry.qml" >/dev/null ||
  fail "rejected schema-v2 manifests can fall through ambiguously"
grep -F 'PanelWindow {' "$runtime_root/shell/SecurePanelSurface.qml" >/dev/null ||
  fail "secure panels are not owned by the Quickshell layer host"
[[ -f $runtime_root/shell/TrustedSurfaceInputMask.qml ]] ||
  fail "secure surfaces lack a reusable trusted input mask"
grep -F 'mask: TrustedSurfaceInputMask {' "$runtime_root/shell/SecurePanelSurface.qml" >/dev/null ||
  fail "secure panels do not use the trusted compositor input mask"
grep -F 'mask: TrustedSurfaceInputMask {' "$runtime_root/shell/SecureOverlaySurface.qml" >/dev/null ||
  fail "secure overlays do not use the trusted compositor input mask"
grep -F 'required property bool dynamicInputRegions' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "typed surface delegates omit the trusted input-region policy"
grep -F 'surface.width === surface.implicitWidth' "$runtime_root/shell/TrustedSurfaceInputMask.qml" >/dev/null ||
  fail "trusted input masks do not fail closed without 1:1 allocation geometry"
grep -F 'surface.inputRegions.length <= root.maximumRegionCount' "$runtime_root/shell/TrustedSurfaceInputMask.qml" >/dev/null ||
  fail "trusted input masks do not bound projected protocol regions"
grep -F 'x: Math.floor((window.width - width) / 2)' "$runtime_root/shell/SecureOverlaySurface.qml" >/dev/null ||
  fail "secure overlay placement can silently round trusted region coordinates"
grep -F 'implicitHeight: Math.min(maximumHeight, screen ? screen.height : maximumHeight)' "$runtime_root/shell/SecurePanelSurface.qml" >/dev/null ||
  fail "secure panel geometry can exceed its admitted height"
grep -F 'anchors.fill: parent' "$runtime_root/shell/SecurePanelSurface.qml" >/dev/null ||
  fail "secure panel allocation does not exactly match its trusted window"
grep -F 'window.barInset + window.panelGap' "$runtime_root/shell/SecurePanelSurface.qml" >/dev/null ||
  fail "secure panels are not offset from the active shell bar"
grep -F 'model: PluginManager.barSurfaces' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure bar surfaces do not consume the typed role model"
grep -F 'property var barEntries: []' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure bar surfaces do not expose a reactive plain-array layout projection"
if ! perl -0ne 'exit(/function\s+configureBar\(target, manifest\).*?var\s+configuredBarId\s*=\s*shell\.activeBarId.*?shell\.securePluginHost\s*!==\s*null.*?configuredBarId\s*!==\s*shell\.defaultBarId.*?!\("securePluginHost"\s+in\s+target\).*?shell\.failedBarId\s*=\s*configuredBarId.*?return.*?shell\.bar\s*=\s*target/s ? 0 : 1)' \
  "$ROOT/shell/shell.qml"; then
  fail "schema-v2 activation does not reject an incompatible custom bar before publication"
fi
grep -F 'does not support sandboxed schema-v2 plugins; using ' "$ROOT/shell/shell.qml" >/dev/null ||
  fail "incompatible custom-bar fallback is not explained to the session log"
grep -F 'next.push({ id: entry.surfaceKey, section: entry.defaultSection })' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure bar layout projection does not preserve its typed id and section"
! grep -F 'barEntriesForScreen' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure bar layout filtering remains hidden behind a host method"
grep -F 'readonly property var secureBarEntries: securePluginHost' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "secure bar entries are not projected into an observable bar property"
grep -F 'readonly property string secureBarOwnerScreenName: securePluginHost' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "secure bar ownership is not projected into an observable bar property"
[[ $(grep -Fc 'root.secureBarEntries, root.secureBarOwnerScreenName)' "$ROOT/shell/plugins/bar/Bar.qml") == 3 ]] ||
  fail "all three declarative bar regions must receive secure layout dependencies"
[[ $(grep -Fc 'screenName: root.windowScreenName(barWindow)' "$ROOT/shell/plugins/bar/Bar.qml") == 6 ]] ||
  fail "bar sections do not receive their shell-owned BarPanel screen"
grep -F 'entries: root.layoutEntries("right", screenName,' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "secure bar slots are not filtered before per-monitor instantiation"
grep -F 'id: barEntryInstances' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure bar delegates are not kept behind the host projection"
grep -F 'Array.isArray(secureEntries)' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "the live bar does not consume the secure host's plain-array projection"
grep -F 'publishedSecureEntries : secureBarEntries' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "imperative bar layout readers do not default to the secure entry projection"
grep -F 'String(publishedSecureOwner || "") : secureBarOwnerScreenName' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "imperative bar layout readers do not default to the secure owner projection"
grep -F 'requestedScreen !== secureOwner' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "secure bar entries can instantiate on a non-owner screen"
grep -F 'secureEntry.section === region' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "secure bar entries bypass their declared section"
grep -F 'Math.min(maximumHeight, bar.vertical ? bar.statusSlot : bar.barSize)' "$runtime_root/shell/SecureBarSurface.qml" >/dev/null ||
  fail "horizontal secure bar surfaces can expand the host bar thickness"
grep -F 'Math.min(maximumWidth, bar.vertical ? bar.barSize : bar.statusSlot)' "$runtime_root/shell/SecureBarSurface.qml" >/dev/null ||
  fail "vertical secure bar surfaces can expand the host bar thickness"
grep -F 'readonly property int statusSlot: Style.bar.statusSlot' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "the native status slot is not available to secure bar projection"
grep -F 'readonly property bool routesOwnPointerInput: true' "$runtime_root/shell/SecureBarSurface.qml" >/dev/null ||
  fail "secure bar surface does not declare native pointer routing ownership"
grep -F 'activeItem.routesOwnPointerInput === true' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "bar slots do not detect native pointer-routing surfaces"
grep -F '&& !slot.routesOwnPointerInput' "$ROOT/shell/plugins/bar/Bar.qml" >/dev/null ||
  fail "ordinary bar click/reorder layer still covers secure surface input"
grep -F 'model: PluginManager.panelSurfaces' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure panels do not consume the typed role model"
grep -F 'model: PluginManager.overlaySurfaces' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure overlays do not consume the typed role model"
if ! perl -0ne 'exit(/Instantiator\s*\{.*?model:\s*PluginManager\.panelSurfaces.*?delegate:\s*QtObject\s*\{.*?id:\s*panelEntry.*?property\s+SecurePanelSurface\s+surface:\s*SecurePanelSurface\s*\{.*?surfaceKey:\s*panelEntry\.surfaceKey/s ? 0 : 1)' \
  "$runtime_root/shell/SecurePluginHost.qml"; then
  fail "secure panel model is not forwarded through its owned typed surface"
fi
if ! perl -0ne 'exit(/Instantiator\s*\{.*?model:\s*PluginManager\.overlaySurfaces.*?delegate:\s*QtObject\s*\{.*?id:\s*overlayEntry.*?property\s+SecureOverlaySurface\s+surface:\s*SecureOverlaySurface\s*\{.*?surfaceKey:\s*overlayEntry\.surfaceKey/s ? 0 : 1)' \
  "$runtime_root/shell/SecurePluginHost.qml"; then
  fail "secure overlay model is not forwarded through its owned typed surface"
fi
if grep -F 'model: PluginManager.surfaces' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  grep -F 'filteredDeclarations' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null; then
  fail "secure surfaces still iterate raw JavaScript declarations"
fi

for surface in SecurePanelSurface.qml SecureOverlaySurface.qml; do
  grep -F 'onSurfaceKeyChanged: attachIfReady()' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface does not retry after its surface identity/readiness changes"
  grep -F 'Window.onWindowChanged: window.attachIfReady()' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface does not retry after its Remote gains a window"
  grep -F 'onWidthChanged: window.attachIfReady()' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface does not retry after its Remote width settles"
  grep -F 'onHeightChanged: window.attachIfReady()' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface does not retry after its Remote height settles"
done
grep -F 'SurfacePolicy.chooseOpenScreen(liveScreenNames(), focusedScreenName)' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure surfaces do not use the shell-owned focused/live-first output policy"
for surface in SecurePanelSurface.qml SecureOverlaySurface.qml; do
  grep -F 'property var assignedScreen: null' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface does not retain its shell-selected output while open"
  grep -F 'assignedScreen = host.screenForIntent(sourceSurface || "", requestedOutput || "")' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface does not resolve its output at closed-to-open time"
  grep -F 'screen: assignedScreen' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface bypasses its shell-owned output selection"
  grep -F 'visible: opened' "$runtime_root/shell/$surface" >/dev/null ||
    fail "$surface visibility is not driven by its finite controller state"
  if grep -F 'visible: screen !== null && opened' "$runtime_root/shell/$surface" >/dev/null; then
    fail "$surface retains the PanelWindow screen/visibility binding loop"
  fi
done
grep -F 'PluginManager.configurePresentationHost(root)' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "secure workers do not receive the bounded host presentation snapshot"
grep -F 'function readSecurePluginPresentation()' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "the shell lacks its authority-free presentation projection"
grep -F 'names.indexOf(requested) !== -1 ? requested' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "requested output placement is not restricted to the live host allowlist"
grep -F 'surfaceScreenName(sourceSurface)' "$runtime_root/shell/SecurePluginHost.qml" >/dev/null ||
  fail "empty or stale output placement does not fall back to the authenticated source surface"
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
