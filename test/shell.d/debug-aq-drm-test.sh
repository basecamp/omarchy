#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

debug="$ROOT/bin/omarchy-debug"

[[ -f $debug ]] || fail "omarchy-debug is in the tree"
grep -q 'omarchy_debug_aq_drm_section' "$debug" || fail "omarchy-debug includes the AQ_DRM_DEVICES section"
pass "omarchy-debug includes the AQ_DRM_DEVICES section"

# shellcheck disable=SC1090
source "$debug"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
HOME=$tmp
unset AQ_DRM_DEVICES

out=$(omarchy_debug_aq_drm_section)
[[ $out == *$'\nprocess: (unset)\n'* || $out == 'process: (unset)'* ]] || fail "unset process env is reported" "$out"
[[ $out == *'uwsm env-hyprland: (absent)'* ]] || fail "missing uwsm env-hyprland is reported" "$out"
[[ $out != *WARNING* ]] || fail "unset env does not warn" "$out"
pass "unset AQ_DRM_DEVICES dumps without warning"

AQ_DRM_DEVICES=
export AQ_DRM_DEVICES
out=$(omarchy_debug_aq_drm_section)
[[ $out == 'process: '$'\n'* || $out == $'process: \n'* ]] || fail "empty process env is reported" "$out"
[[ $out != *WARNING* ]] || fail "empty env does not warn" "$out"
pass "empty AQ_DRM_DEVICES dumps without warning"
unset AQ_DRM_DEVICES

AQ_DRM_DEVICES='/dev/dri/by-path/pci-0000:13:00.0-card'
export AQ_DRM_DEVICES
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'process: /dev/dri/by-path/pci-0000:13:00.0-card'* ]] || fail "process by-path is dumped" "$out"
[[ $out == *'WARNING: process uses PCI by-path names'* ]] || fail "process by-path warns" "$out"
pass "process by-path AQ_DRM_DEVICES warns"
unset AQ_DRM_DEVICES

mkdir -p "$tmp/.config/uwsm"
printf 'export AQ_DRM_DEVICES=/dev/dri/igpu\n' >"$tmp/.config/uwsm/env-hyprland"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'uwsm env-hyprland: export AQ_DRM_DEVICES=/dev/dri/igpu'* ]] || fail "uwsm udev name is dumped" "$out"
[[ $out != *WARNING* ]] || fail "colon-free udev name does not warn" "$out"
pass "colon-free uwsm pin dumps without warning"

printf 'export AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:13:00.0-card\n' >"$tmp/.config/uwsm/env-hyprland"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'WARNING: uwsm env-hyprland uses PCI by-path names'* ]] || fail "uwsm by-path warns" "$out"
pass "uwsm by-path pin warns"

printf 'export AQ_DRM_DEVICES=/dev/dri/card1\n' >"$tmp/.config/uwsm/env-hyprland"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'WARNING: uwsm env-hyprland pins /dev/dri/cardN'* ]] || fail "uwsm cardN warns" "$out"
pass "uwsm cardN pin warns"

printf '# AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:13:00.0-card\n' >"$tmp/.config/uwsm/env-hyprland"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'uwsm env-hyprland: (not set)'* ]] || fail "comment-only uwsm file is ignored" "$out"
[[ $out != *WARNING* ]] || fail "comment-only uwsm file does not warn" "$out"
pass "comment-only uwsm file does not warn"

mkdir -p "$tmp/.config/uwsm/env-hyprland.d"
printf '# Rewrite PCI by-path AQ_DRM_DEVICES after user env-hyprland.\n' >"$tmp/.config/uwsm/env-hyprland.d/99-omarchy-aq-drm"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'uwsm env-hyprland.d: (not set)'* ]] || fail "comment-only drop-in is ignored" "$out"
[[ $out != *WARNING* ]] || fail "comment-only drop-in does not warn" "$out"
pass "comment-only drop-in does not warn"

printf 'export AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:03:00.0-card\n' >"$tmp/.config/uwsm/env-hyprland.d/10-user"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'uwsm env-hyprland.d/10-user: export AQ_DRM_DEVICES=/dev/dri/by-path/pci-0000:03:00.0-card'* ]] || fail "drop-in by-path is dumped" "$out"
[[ $out == *'WARNING: uwsm env-hyprland.d/10-user uses PCI by-path names'* ]] || fail "drop-in by-path warns" "$out"
pass "uwsm drop-in by-path pin warns"

rm -f "$tmp/.config/uwsm/env-hyprland" "$tmp/.config/uwsm/env-hyprland.d/10-user"
mkdir -p "$tmp/.config/hypr"
printf 'hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:13:00.0-card")\n' >"$tmp/.config/hypr/hyprland.lua"
printf 'hl.env("XCURSOR_SIZE", "24")\n' >"$tmp/.config/hypr/envs.lua"
out=$(omarchy_debug_aq_drm_section)
[[ $out == *'hypr hyprland.lua: hl.env("AQ_DRM_DEVICES", "/dev/dri/by-path/pci-0000:13:00.0-card")'* ]] || fail "hypr lua by-path is dumped" "$out"
[[ $out == *'WARNING: hypr hyprland.lua uses PCI by-path names'* ]] || fail "hypr lua by-path warns" "$out"
[[ $out != *'hypr envs.lua'* ]] || fail "unrelated hypr lua is omitted" "$out"
pass "hypr lua by-path pin warns"
