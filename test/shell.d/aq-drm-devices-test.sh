#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/default/uwsm/sanitize-aq-drm-devices"
dropin="$ROOT/config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
migration="$ROOT/migrations/1787934927.sh"

[[ -f $helper ]] || fail "sanitize helper is in the tree"
[[ -f $dropin ]] || fail "uwsm env-hyprland.d drop-in is in the tree"
[[ -f $migration ]] || fail "migration is in the tree"

grep -q 'sanitize-aq-drm-devices' "$dropin" || fail "drop-in sources the sanitize helper"
pass "drop-in sources the sanitize helper"

run_sanitize() {
  local value=$1
  AQ_DRM_DEVICES=$value
  export AQ_DRM_DEVICES
  # shellcheck disable=SC1090
  . "$helper"
  if [[ -n ${AQ_DRM_DEVICES+x} ]]; then
    printf '%s' "$AQ_DRM_DEVICES"
  else
    printf '%s' "__UNSET__"
  fi
}

[[ $(run_sanitize "") == "" ]] || fail "empty AQ_DRM_DEVICES is a no-op"
pass "empty AQ_DRM_DEVICES is a no-op"

[[ $(run_sanitize "/dev/dri/amd-igpu") == "/dev/dri/amd-igpu" ]] || fail "colon-free pin is left alone"
pass "colon-free pin is left alone"

[[ $(run_sanitize "/dev/dri/card0:/dev/dri/card1") == "/dev/dri/card0:/dev/dri/card1" ]] || fail "colon-free list is left alone"
pass "colon-free list is left alone"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0-card") == "__UNSET__" ]] || fail "missing by-path is dropped so Aquamarine cannot split it"
pass "missing by-path is dropped so Aquamarine cannot split it"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0-card:/dev/dri/by-path/pci-0000:03:00.0-card") == "__UNSET__" ]] || fail "missing by-path list is dropped"
pass "missing by-path list is dropped"

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/dri"
: >"$dir/dri/card0"
: >"$dir/dri/card1"

[[ $(run_sanitize "$dir/dri/card0:$dir/dri/card1") == "$dir/dri/card0:$dir/dri/card1" ]] || fail "existing cardN list is left alone"
pass "existing cardN list is left alone"

mixed=$(run_sanitize "$dir/dri/card0:/dev/dri/by-path/pci-0000:13:00.0-card")
[[ $mixed == "$dir/dri/card0" ]] || fail "usable card is kept when a by-path sibling is dropped" "$mixed"
pass "usable card is kept when a by-path sibling is dropped"

by_dir="$dir/dri/by-path"
by_path="$by_dir/pci-0000:13:00.0-card"
if mkdir -p "$by_dir" && ln -s "$dir/dri/card0" "$by_path" 2>/dev/null; then
  resolved=$(readlink -f "$by_path" 2>/dev/null || true)
  if [[ -n $resolved && $resolved != *:* && $resolved == "$dir/dri/card0" ]]; then
    [[ $(run_sanitize "$by_path") == "$dir/dri/card0" ]] || fail "by-path symlink is resolved to the DRM node"
    pass "by-path symlink is resolved to the DRM node"

    [[ $(run_sanitize "$by_path:/dev/dri/by-path/pci-0000:03:00.0-card") == "$dir/dri/card0" ]] || fail "resolved by-path is kept when a missing sibling is dropped"
    pass "resolved by-path is kept when a missing sibling is dropped"
  else
    pass "by-path filenames are not usable here; skip symlink resolution"
  fi
else
  pass "by-path filenames are not usable here; skip symlink resolution"
fi

dropin_out=$(
  OMARCHY_PATH=$ROOT
  export OMARCHY_PATH
  AQ_DRM_DEVICES="/dev/dri/by-path/pci-0000:13:00.0-card"
  export AQ_DRM_DEVICES
  # shellcheck disable=SC1090
  . "$dropin"
  if [[ -n ${AQ_DRM_DEVICES+x} ]]; then
    printf '%s' "$AQ_DRM_DEVICES"
  else
    printf '%s' "__UNSET__"
  fi
)
[[ $dropin_out == "__UNSET__" ]] || fail "sourcing the drop-in sanitizes AQ_DRM_DEVICES" "$dropin_out"
pass "sourcing the drop-in sanitizes AQ_DRM_DEVICES"

test_home=$(mktemp -d)
dst="$test_home/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ -f $dst ]] || fail "migration installs the drop-in"
cmp -s "$dst" "$dropin" || fail "migration copies the shipped drop-in"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ -f $dst ]] || fail "migration is idempotent"
echo changed >"$dst"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ $(cat "$dst") == changed ]] || fail "migration does not overwrite an existing drop-in"
pass "migration installs the drop-in without clobbering"
rm -rf "$test_home"
