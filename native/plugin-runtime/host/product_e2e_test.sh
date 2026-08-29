#!/bin/bash

set -euo pipefail

host=$1
worker=$2
permission_store=$3
fixture_root=$4
dynamic_grant=$5
network_definition=$6

[[ -x /usr/bin/bwrap ]] || exit 77

test_root=$(mktemp -d /tmp/omarchy-plugin-product-e2e.XXXXXX)
cleanup() {
  jobs -pr | xargs -r kill
  if [[ ${OMARCHY_PLUGIN_E2E_KEEP_TMP:-0} == 1 ]]; then
    echo "product e2e retained $test_root" >&2
    return
  fi
  chmod -R u+w "$test_root"
  rm -rf "$test_root"
}
trap cleanup EXIT

fail() {
  echo "product e2e: $1" >&2
  exit 1
}

prepare() {
  local name=$1
  local run=$test_root/$name
  mkdir -m 0700 -p "$run/plugins" "$run/grants" "$run/state" "$run/audit"
  cp -a "$fixture_root/$name" "$run/plugins/$name"
  find "$run/plugins/$name" -type d -exec chmod 0555 {} +
  find "$run/plugins/$name" -type f -exec chmod 0444 {} +
  env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 \
    OMARCHY_PLUGIN_LIVE_LAB_ENABLED=I_ACCEPT_LAB_RISK \
    "$host" --identify-plugin-live-lab "$run/plugins/$name" >"$run/identity"
  local tree
  tree=$(sed -n 's/^tree=//p' "$run/identity")
  [[ $tree =~ ^[0-9a-f]{64}$ ]] || fail "$name identity missing"
}

binding_args() {
  local name=$1
  local run=$test_root/$name plugin tree request
  plugin=$(sed -n 's/^plugin=//p' "$run/identity")
  tree=$(sed -n 's/^tree=//p' "$run/identity")
  request=$(sed -n 's/^request=//p' "$run/identity")
  printf '%s\n' --schema-version 2 --plugin "$plugin" --revision "$tree" \
    --source-request "$request" --generation 1
}

grant_capability() {
  local name=$1 request_kind=$2 capability=$3
  local run=$test_root/$name command output
  mapfile -t binding < <(binding_args "$name")
  printf -v command '%q ' env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 \
    "$permission_store" grant --store "$run/grants" "${binding[@]}" \
    "$request_kind" "$capability" --capability "${capability%%=*}"
  output=$(printf 'grant\n' | script -qec "$command" /dev/null 2>&1) || {
    echo "$output" >&2
    fail "$name grant failed"
  }
  local plugin
  plugin=$(sed -n 's/^plugin=//p' "$run/identity")
  env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 \
    OMARCHY_PLUGIN_LIVE_LAB_ENABLED=I_ACCEPT_LAB_RISK \
    "$host" --activate-plugin-live-lab "$run/grants" "$plugin"
}

launch() {
  local name=$1 calls=$2 frames=$3 render_packets=$4 mutation=$5 post_mutation_frames=$6 post_call_frames=$7
  local run=$test_root/$name tree
  tree=$(sed -n 's/^tree=//p' "$run/identity")
  env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 \
    OMARCHY_PLUGIN_LIVE_LAB_ENABLED=I_ACCEPT_LAB_RISK \
    OMARCHY_PLUGIN_E2E_EXPECT_CALLS=$calls \
    OMARCHY_PLUGIN_E2E_EXPECT_FRAMES=$frames \
    OMARCHY_PLUGIN_E2E_EXPECT_RENDER_PACKETS=$render_packets \
    OMARCHY_PLUGIN_E2E_EXPECT_MUTATION=$mutation \
    OMARCHY_PLUGIN_E2E_EXPECT_POST_MUTATION_FRAMES=$post_mutation_frames \
    OMARCHY_PLUGIN_E2E_EXPECT_POST_CALL_FRAMES=$post_call_frames \
    "$host" --preview-plugin-live-lab "$run/plugins/$name" "$tree" \
    "$run/grants" "$run/state" "$run/audit" "$worker" ignored ignored
}

prepare lab-authorized
grant_capability lab-authorized --required storage.private@1=quota:65536:4096
launch lab-authorized 2 1 2 2 0 1 >"$test_root/lab-authorized/host.log" 2>&1 || {
  status=$?
  cat "$test_root/lab-authorized/host.log" >&2
  fail "authorized host failed with $status"
}
grep -q 'PRODUCT_E2E complete calls 2 frames' "$test_root/lab-authorized/host.log" || \
  fail "authorized broker/frame terminal evidence missing"
find "$test_root/lab-authorized/state" -type f -size +0c -print -quit | grep -q . || \
  fail "authorized provider state missing"
find "$test_root/lab-authorized/audit" -type f -size +0c -print -quit | grep -q . || \
  fail "authorized audit missing"

prepare lab-dynamic-radio
dynamic_run=$test_root/lab-dynamic-radio
dynamic_plugin=$(sed -n 's/^plugin=//p' "$dynamic_run/identity")
dynamic_tree=$(sed -n 's/^tree=//p' "$dynamic_run/identity")
dynamic_request=$(sed -n 's/^request=//p' "$dynamic_run/identity")
"$dynamic_grant" "$dynamic_run/plugins/lab-dynamic-radio/manifest.json" \
  "$dynamic_plugin" "$dynamic_tree" "$dynamic_request" \
  "$dynamic_run/grants" "$network_definition" || fail "dynamic grant review failed"
launch lab-dynamic-radio 1 2 2 3 1 1 >"$dynamic_run/host.log" 2>&1 &
dynamic_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  grep -q 'PRODUCT_E2E frame 1' "$dynamic_run/host.log" && break
  sleep 0.05
done
grep -q 'PRODUCT_E2E frame 1' "$dynamic_run/host.log" || fail "dynamic Radio startup frame missing"
"$dynamic_grant" revoke "$dynamic_run/grants" "$dynamic_plugin" network.fetch || \
  fail "dynamic Radio revoke failed"
wait "$dynamic_pid" || {
  cat "$dynamic_run/host.log" >&2
  fail "dynamic Radio host failed"
}
grep -q 'PRODUCT_E2E complete calls 1 frames 2' "$dynamic_run/host.log" || \
  fail "dynamic Radio broker/frame terminal evidence missing"
find "$dynamic_run/audit" -type f -size +0c -print -quit | grep -q . || \
  fail "dynamic Radio audit missing"

prepare lab-denied
grant_capability lab-denied --required storage.private@1=quota:65536:4096
launch lab-denied 1 1 2 2 0 1 >"$test_root/lab-denied/host.log" 2>&1 || {
  cat "$test_root/lab-denied/host.log" >&2
  fail "denied host failed"
}
grep -q 'PRODUCT_E2E complete calls 1 frames' "$test_root/lab-denied/host.log" || \
  fail "denied broker/frame terminal evidence missing"
authorized_hash=$(awk '/PRODUCT_E2E frame/ { hash = $4 } END { print hash }' "$test_root/lab-authorized/host.log")
denied_hash=$(awk '/PRODUCT_E2E frame/ { hash = $4 } END { print hash }' "$test_root/lab-denied/host.log")
[[ -n $authorized_hash && -n $denied_hash && $authorized_hash != "$denied_hash" ]] || \
  fail "allowed and denied QML terminal frames were not distinct"
find "$test_root/lab-denied/audit" -type f -size +0c -print -quit | grep -q . || \
  fail "denied audit missing"

prepare lab-permission
grant_capability lab-permission --optional notifications.send@1=tokens:proof
OMARCHY_PLUGIN_E2E_CLICK_X=100 OMARCHY_PLUGIN_E2E_CLICK_Y=100 \
  OMARCHY_PLUGIN_E2E_CLICK_AFTER_MUTATION=3 \
  launch lab-permission 0 2 3 3 1 0 >"$test_root/lab-permission/host.log" 2>&1 &
permission_pid=$!
for ((attempt = 0; attempt < 100; attempt++)); do
  grep -q 'PRODUCT_E2E frame 1' "$test_root/lab-permission/host.log" && break
  sleep 0.05
done
grep -q 'PRODUCT_E2E frame 1' "$test_root/lab-permission/host.log" || fail "permission startup frame missing"
mapfile -t permission_binding < <(binding_args lab-permission)
env OMARCHY_PLUGIN_SCHEMA_V2_ENABLED=1 "$permission_store" revoke \
  --store "$test_root/lab-permission/grants" "${permission_binding[@]}" \
  --optional notifications.send@1=tokens:proof \
  --capability notifications.send@1 >/dev/null
wait "$permission_pid" || {
  cat "$test_root/lab-permission/host.log" >&2
  fail "permission revoke host failed"
}
permission_completion=$(awk '/PRODUCT_E2E complete calls 0/ { print; exit }' \
  "$test_root/lab-permission/host.log")
[[ $permission_completion =~ post_mutation_frames\ ([1-9][0-9]*) &&
   $permission_completion =~ grant_mutation\ 3 ]] || \
  fail "permission revoke did not produce an authenticated follow-up frame"

echo "product host real-bwrap e2e: PASS"
