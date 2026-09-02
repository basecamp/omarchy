#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

shell_qml="$ROOT/shell/shell.qml"
bar_qml="$ROOT/shell/plugins/bar/Bar.qml"
plugin_shell_api="$ROOT/shell/services/PluginShellApi.qml"

# Normalize horizontal and vertical whitespace so the wiring assertions survive
# harmless QML reflow. The runtime fixture below behaviorally covers
# PluginShellApi and AuthServiceStore; these checks remain the guard for their
# integration through shell.qml and Bar.qml, including without a compositor.
qml_matches() {
  local file=$1
  local pattern=$2

  tr '\n\r\t' '   ' < "$file" | grep -Eq "$pattern"
}

qml_matches "$shell_qml" 'comp\.createObject\( *manifest\.__isFirstParty *&& *!authenticationService *\? *serviceHost *: *null *\)' ||
  fail "third-party and authentication services are detached from the host object tree"
qml_matches "$shell_qml" 'AuthServiceStore\.put\( *key, *inst *\)' ||
  fail "authentication services are retained outside the host service map"
qml_matches "$shell_qml" 'AuthServiceStore\.updateManifest\( *id, *shell\.publicPluginManifest\( *m *\) *\)' ||
  fail "kept authentication services receive only a public manifest snapshot"
qml_matches "$shell_qml" 'if *\( *!serviceKeepLoaded\( *authenticationId *\) *\) *AuthServiceStore\.destroy\( *authenticationId *\)' ||
  fail "keepLoaded authentication services survive plugin rescans"
pass "third-party and authentication services are detached from the host object tree"

qml_matches "$shell_qml" 'inst\.shell *= *shell\.pluginShellFor\( *manifest *\)' ||
  fail "service plugins receive a scoped shell facade"
qml_matches "$shell_qml" 'item\.shell *= *shell\.pluginShellFor\( *panelEntry\.manifest *\)' ||
  fail "panel plugins receive a scoped shell facade"
qml_matches "$shell_qml" 'target\.shell *= *shell\.pluginShellFor\( *manifest *\)' ||
  fail "full-bar plugins receive a scoped shell facade"
pass "third-party entry points receive scoped shell facades"

if qml_matches "$plugin_shell_api" 'function +pluginShellForId\('; then
  fail "replacement-bar facade exposes a generic plugin-shell factory"
fi
qml_matches "$bar_qml" 'else if *\( *root\.shell *&& *typeof root\.shell\.pluginShellForBarEntry *=== *"function" *\) *\{[^}]*pluginShell *= *root\.shell\.pluginShellForBarEntry\( *key, *moduleName *\)' ||
  fail "replacement bars do not fall back to a service-less entry facade"
pass "replacement bars cannot manufacture another plugin's service facade"

qml_matches "$shell_qml" 'target\.barConfig *= *shell\.barConfigFor\( *manifest *\)' ||
  fail "initial replacement-bar configuration is not detached"
qml_matches "$shell_qml" 'bar\.barConfig *= *shell\.barConfigFor\( *shell\.activeBarManifest *\)' ||
  fail "replacement-bar configuration updates are not detached"
pass "replacement bars receive detached configuration snapshots"

qml_matches "$bar_qml" 'target\.bar *= *firstParty *\? *root *: *root\.pluginBarApiFor\( *pluginApiId, *moduleName, *registered *\)' ||
  fail "third-party widgets receive a bar facade instead of the host bar"
qml_matches "$bar_qml" 'api\.clickTargets *= *root\.pluginClickTargets\( *api\.pluginId *\)' ||
  fail "third-party bar facades exclude other widgets from their object graph"
pass "third-party widgets receive a bar facade instead of the host bar"

qml_matches "$shell_qml" 'widgets: *shell\.publicBarWidgetSnapshot\( *\)' ||
  fail "third-party widget registries receive detached snapshots"
qml_matches "$bar_qml" 'root\.markPluginObject\( *pluginId, *target, *"clickTarget" *\)' ||
  fail "third-party bar-object ownership is stamped by the host callback"
qml_matches "$bar_qml" 'root\.markPluginObject\( *pluginId, *owner, *"popout" *\)' ||
  fail "owner-less popouts receive trusted ownership before activation"
qml_matches "$shell_qml" 'manifest\.__hostCapabilities\.indexOf\( *"authentication" *\)' ||
  fail "authentication isolation follows host-stamped capabilities"
pass "registry mutation and ownership boundaries are host-controlled"

qml_matches "$bar_qml" 'root\.moduleWidgets\( *moduleName *\)' ||
  fail "custom bar module widget lookups use their real module name"
qml_matches "$shell_qml" 'shell\.pluginShellForBarEntry\( *cacheKey *\+ *":" *\+ *ownerId, *moduleName *\)' ||
  fail "full-bar plugins receive a scoped settings facade for custom modules"
pass "custom bar modules retain settings and popout identity"

if qml_matches "$bar_qml" 'on(Foreground|BarForeground|Background|Urgent|FontFamily|Vertical|BarSize|Transparent)Changed: *sync'; then
  fail "animated scalar properties still trigger full facade resyncs"
fi
qml_matches "$bar_qml" 'api\.foreground *= *Qt\.binding\( *function\( *\) *\{ *return root\.foreground *\} *\)' ||
  fail "third-party bar scalar mirrors use bindings"
qml_matches "$shell_qml" 'shell\.prunePluginApis\( *\)' ||
  fail "disabled plugin facade caches are pruned"
pass "plugin facade synchronization is bounded"

qml_matches "$shell_qml" 'descriptor\.profile *!== *expectedProfile[^}]*shell\.revokePluginShellApi\( *shellKey *\)' ||
  fail "manifest capability changes do not revoke cached plugin facades"
qml_matches "$shell_qml" 'shell\.barPluginMayControl\( *currentManifest\( *\), *requestedId *\)' ||
  fail "bar lifecycle callbacks do not validate the current manifest"
qml_matches "$shell_qml" 'return hasCurrentBarCapabilities\( *\) *\? *shell\.mutatePluginBarConfig\( *mutator *\) *: *false' ||
  fail "bar configuration mutation does not validate the current manifest"
pass "manifest changes revoke cached facade capabilities"

qml_matches "$shell_qml" 'shell\.serviceFor\( *shell\.pluginRegistry\.resolveEnabledId\( *id *\) *\)' ||
  fail "narrow first-party service proxies do not resolve enabled clones"
qml_matches "$shell_qml" 'return serviceFor\( *shell\.pluginRegistry\.resolveEnabledId\( *pluginId *\) *\)' ||
  fail "trusted first-party service lookups do not resolve enabled clones"
qml_matches "$shell_qml" 'allowOwnService *&& *shell\.pluginOwnsTarget\( *key, *requestedId *\)[^}]*return shell\.pluginServiceFor\( *key, *requestedId *\)' ||
  fail "cloned widgets cannot use a source id to reach their own service"
pass "service facades resolve enabled clones without widening replacement-bar access"

require_compositor "plugin authentication boundary runtime test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping plugin authentication boundary runtime test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
config_dir="$TMPDIR/plugin-auth-boundary"
mkdir -p "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/plugin-auth-boundary/"*.qml "$config_dir/"
ln -s "$ROOT/shell/services" "$config_dir/services"

OMARCHY_QML_TEST_RESULT="$result" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$log" >&2
    fail "plugin authentication boundary fixture exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "plugin authentication boundary runtime test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  jq . "$result" >&2
  sed -n '1,220p' "$log" >&2
  fail "plugin authentication boundary runtime behavior"
fi

pass "plugin authentication boundary runtime behavior"
