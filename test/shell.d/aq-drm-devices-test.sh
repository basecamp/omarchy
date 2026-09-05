#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

helper="$ROOT/default/uwsm/sanitize-aq-drm-devices"
dropin="$ROOT/config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
migration="$ROOT/migrations/1787934927.sh"

[[ -f $helper ]] || fail "sanitize helper is in the tree"
[[ -f $dropin ]] || fail "uwsm env-hyprland.d drop-in is in the tree"
[[ ! -e $ROOT/config/uwsm/env-hyprland.d/99-omarchy-aq-drm ]] || fail "numeric 99- drop-in was renamed to zz-"
[[ -f $migration ]] || fail "migration is in the tree"

grep -q 'sanitize-aq-drm-devices' "$dropin" || fail "drop-in sources the sanitize helper"
pass "drop-in sources the sanitize helper"

sorted=$(printf '%s\n' '99-omarchy-aq-drm' 'my_vars' 'zz-omarchy-aq-drm' | LC_ALL=C sort | tail -n 1)
[[ $sorted == "zz-omarchy-aq-drm" ]] || fail "zz- sorts after numeric and alphabetic drop-in names"
pass "zz- sorts after numeric and alphabetic drop-in names"

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

[[ $(run_sanitize "") == "__UNSET__" ]] || fail "empty AQ_DRM_DEVICES is unset"
pass "empty AQ_DRM_DEVICES is unset"

[[ $(run_sanitize "/dev/dri/amd-igpu") == "/dev/dri/amd-igpu" ]] || fail "colon-free pin is left alone"
pass "colon-free pin is left alone"

[[ $(run_sanitize "/dev/dri/card0:/dev/dri/card1") == "/dev/dri/card0:/dev/dri/card1" ]] || fail "colon-free list is left alone"
pass "colon-free list is left alone"

[[ $(run_sanitize "amd-igpu:nvidia-dgpu") == "amd-igpu:nvidia-dgpu" ]] || fail "udev-name list is left alone"
pass "udev-name list is left alone"

[[ $(run_sanitize "/dev/dri/card0:card1") == "/dev/dri/card0:card1" ]] || fail "mixed colon-free list is left alone"
pass "mixed colon-free list is left alone"

[[ $(run_sanitize "amd-pci-dgpu:card1") == "amd-pci-dgpu:card1" ]] || fail "udev alias containing pci- is not glued to the next pin"
pass "udev alias containing pci- is not glued to the next pin"

[[ $(run_sanitize "/dev/dri/card1::/does-not-exist") == "/dev/dri/card1:/does-not-exist" ]] || fail "empty list component does not drop the previous GPU"
pass "empty list component does not drop the previous GPU"

[[ $(run_sanitize "/dev/dri/card1:") == "/dev/dri/card1" ]] || fail "trailing colon is stripped"
pass "trailing colon is stripped"

[[ $(run_sanitize "/dev/dri/card1:::/dev/dri/card9999") == "/dev/dri/card1:/dev/dri/card9999" ]] || fail "two empty components do not drop the previous GPU"
pass "two empty components do not drop the previous GPU"

[[ $(run_sanitize "/dev/dri/card1::::/dev/dri/card9999") == "/dev/dri/card1:/dev/dri/card9999" ]] || fail "three empty components do not drop the previous GPU"
pass "three empty components do not drop the previous GPU"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0-card") == "__UNSET__" ]] || fail "missing by-path is dropped so Aquamarine cannot split it"
pass "missing by-path is dropped so Aquamarine cannot split it"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0-card:/dev/dri/by-path/pci-0000:03:00.0-card") == "__UNSET__" ]] || fail "missing by-path list is dropped"
pass "missing by-path list is dropped"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0-card:rel/mygpu") == "rel/mygpu" ]] || fail "stale by-path does not swallow a following relative entry"
pass "stale by-path does not swallow a following relative entry"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0-card:card1") == "card1" ]] || fail "stale by-path does not swallow a following cardN pin"
pass "stale by-path does not swallow a following cardN pin"

[[ $(run_sanitize "/dev/dri/by-path/pci-0000:13:00.0:rel/mygpu") == "rel/mygpu" ]] || fail "incomplete by-path does not absorb a slash-containing continuation"
pass "incomplete by-path does not absorb a slash-containing continuation"

[[ $(run_sanitize "/dev/dri/by-path/platform-omarchy-test-card") == "__UNSET__" ]] || fail "missing colon-free by-path is dropped instead of exported"
pass "missing colon-free by-path is dropped instead of exported"

[[ $(run_sanitize "/dev/dri/by-path/platform-omarchy-test-card:card1") == "card1" ]] || fail "missing colon-free by-path does not export an unusable list"
pass "missing colon-free by-path does not export an unusable list"

usb_missing="/dev/dri/by-path/pci-0000:00:14.0-usb-0:8:1.0-card"
[[ $(run_sanitize "$usb_missing") == "__UNSET__" ]] || fail "missing USB by-path is dropped instead of exporting debris"
pass "missing USB by-path is dropped instead of exporting debris"

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
mkdir -p "$dir/dri"
: >"$dir/dri/card0"
: >"$dir/dri/card1"

[[ $(run_sanitize "$dir/dri/card0:$dir/dri/card1") == "$dir/dri/card0:$dir/dri/card1" ]] || fail "existing cardN list is left alone"
pass "existing cardN list is left alone"

[[ $(run_sanitize "$dir/dri/card0::$dir/dri/card1") == "$dir/dri/card0:$dir/dri/card1" ]] || fail "empty component between existing cards keeps both"
pass "empty component between existing cards keeps both"

mixed=$(run_sanitize "$dir/dri/card0:/dev/dri/by-path/pci-0000:13:00.0-card")
[[ $mixed == "$dir/dri/card0" ]] || fail "usable card is kept when a by-path sibling is dropped" "$mixed"
pass "usable card is kept when a by-path sibling is dropped"

usb_then_card=$(run_sanitize "$usb_missing:$dir/dri/card0")
[[ $usb_then_card == "$dir/dri/card0" ]] || fail "usable card is kept when a missing USB by-path sibling is dropped" "$usb_then_card"
pass "usable card is kept when a missing USB by-path sibling is dropped"

by_dir="$dir/dri/by-path"
by_path="$by_dir/pci-0000:13:00.0-card"
if mkdir -p "$by_dir" && ln -s "$dir/dri/card0" "$by_path" 2>/dev/null; then
  resolved=$(readlink -e "$by_path" 2>/dev/null || true)
  if [[ -n $resolved && $resolved != *:* && $resolved == "$dir/dri/card0" ]]; then
    [[ $(run_sanitize "$by_path") == "$dir/dri/card0" ]] || fail "by-path symlink is resolved to the DRM node"
    pass "by-path symlink is resolved to the DRM node"

    [[ $(run_sanitize "$by_path:/dev/dri/by-path/pci-0000:03:00.0-card") == "$dir/dri/card0" ]] || fail "resolved by-path is kept when a missing sibling is dropped"
    pass "resolved by-path is kept when a missing sibling is dropped"

    [[ $(run_sanitize "$by_path:$dir/dri/card1") == "$dir/dri/card0:$dir/dri/card1" ]] || fail "resolved by-path keeps a following colon-free pin"
    pass "resolved by-path keeps a following colon-free pin"

    [[ $(run_sanitize "$by_path:rel/mygpu") == "$dir/dri/card0:rel/mygpu" ]] || fail "resolved by-path keeps a following relative entry"
    pass "resolved by-path keeps a following relative entry"

    plat_path="$by_dir/platform-omarchy-test-card"
    if ln -s "$dir/dri/card0" "$plat_path" 2>/dev/null; then
      [[ $(run_sanitize "$plat_path") == "$dir/dri/card0" ]] || fail "colon-free by-path is resolved to the DRM node"
      pass "colon-free by-path is resolved to the DRM node"
    else
      printf 'skip - cannot create a colon-free by-path symlink here\n'
    fi

    usb_path="$by_dir/pci-0000:00:14.0-usb-0:8:1.0-card"
    if ln -s "$dir/dri/card0" "$usb_path" 2>/dev/null; then
      [[ $(run_sanitize "$usb_path") == "$dir/dri/card0" ]] || fail "USB by-path with extra colons is resolved to the DRM node"
      pass "USB by-path with extra colons is resolved to the DRM node"
    else
      printf 'skip - cannot create a USB by-path symlink here\n'
    fi

    dangling="$by_dir/pci-0000:03:00.0-card"
    if ln -s "$dir/dri/card99" "$dangling" 2>/dev/null; then
      [[ $(run_sanitize "$dangling") == "__UNSET__" ]] || fail "dangling by-path is dropped"
      pass "dangling by-path is dropped"
    else
      printf 'skip - cannot create a dangling by-path symlink here\n'
    fi
  else
    printf 'skip - by-path filenames are not usable here; symlink resolution not exercised\n'
  fi
else
  printf 'skip - by-path filenames are not usable here; symlink resolution not exercised\n'
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
dst="$test_home/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
mkdir -p "$(dirname "$dst")"
if ln -s "$test_home/missing-drop-in" "$dst" 2>/dev/null; then
  HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null || fail "migration no-ops on a dangling drop-in symlink"
  [[ -L $dst ]] || fail "migration leaves a dangling drop-in symlink in place"
  pass "migration no-ops on a dangling drop-in symlink"
else
  printf 'skip - cannot create a dangling drop-in symlink here\n'
fi
rm -rf "$test_home"

test_home=$(mktemp -d)
dst="$test_home/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
old="$test_home/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
mkdir -p "$(dirname "$old")"
echo leftover >"$old"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ -f $dst ]] || fail "migration installs the zz- drop-in beside an unrelated 99- file"
[[ $(cat "$old") == leftover ]] || fail "migration leaves an unrelated 99- file in place"
pass "migration leaves an unrelated 99- file in place"
rm -rf "$test_home"

test_home=$(mktemp -d)
dst="$test_home/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
old="$test_home/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
mkdir -p "$(dirname "$old")"
printf '%s\n' '# mention sanitize-aq-drm-devices in a comment' 'export FOO=1' >"$old"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ -f $dst ]] || fail "migration installs the zz- drop-in beside a 99- comment mention"
[[ -f $old ]] || fail "migration leaves a 99- file that only mentions the helper"
pass "migration leaves a 99- file that only mentions the helper"
rm -rf "$test_home"

test_home=$(mktemp -d)
dst="$test_home/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
old="$test_home/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
mkdir -p "$(dirname "$old")"
printf '%s\n' '# leftover' '[ -r "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices" ] && . "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices"' >"$old"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ -f $dst ]] || fail "migration installs the zz- drop-in beside an edited leftover 99-"
[[ -f $old ]] || fail "migration leaves a 99- file that is not the exact shipped drop-in"
pass "migration leaves a 99- file that is not the exact shipped drop-in"
rm -rf "$test_home"

test_home=$(mktemp -d)
dst="$test_home/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
old="$test_home/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
mkdir -p "$(dirname "$old")"
printf '%s\n' \
  '# Rewrite PCI by-path AQ_DRM_DEVICES after user env-hyprland.' \
  "# Aquamarine splits on ':' (hyprwm/aquamarine#167)." \
  '[ -r "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices" ] && . "${OMARCHY_PATH%/}/default/uwsm/sanitize-aq-drm-devices"' >"$old"
HOME=$test_home OMARCHY_PATH=$ROOT bash -euo pipefail "$migration" >/dev/null
[[ -f $dst ]] || fail "migration installs the zz- drop-in"
[[ ! -e $old ]] || fail "migration removes the leftover sanitizer 99- drop-in"
pass "migration replaces a leftover sanitizer 99- drop-in with zz-"
rm -rf "$test_home"

test_home=$(mktemp -d)
dst="$test_home/.config/uwsm/env-hyprland.d/zz-omarchy-aq-drm"
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
