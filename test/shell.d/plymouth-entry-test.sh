#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The preview renders with ImageMagick and ends by opening the result in imv.
# Neither is needed to assert the geometry, so skip when magick is absent and
# stub imv so the command never opens a viewer.
if ! command -v magick >/dev/null; then
  pass "no magick; skipping plymouth entry field geometry test"
  exit 0
fi

stub=$(mktemp -d)
scratch=$(mktemp -d)
printf '#!/bin/bash\nexit 0\n' >"$stub/imv"
chmod +x "$stub/imv"
export PATH="$stub:$PATH"
export OMARCHY_PATH="$ROOT"
trap 'rm -rf "$stub" "$scratch"' EXIT

preview="$ROOT/bin/omarchy-plymouth-preview"

# Renders a preview for a logo of the given size and prints the top edge (y) of
# the bright pixels, which track the entry field's top. Prints nothing when there
# are no bright pixels. Returns non-zero if the preview command itself fails.
entry_top_y() {
  local logo_w="$1" logo_h="$2"
  local logo="$scratch/logo-${logo_w}x${logo_h}.png"
  local out="$scratch/out-${logo_w}x${logo_h}.png"
  magick -size "${logo_w}x${logo_h}" xc:black "$logo"
  if ! "$preview" '#000000' '#ffffff' "$logo" "$out"; then
    return 1
  fi
  local bbox
  bbox=$(magick "$out" -threshold 50% -format '%[bounding-box]' info: 2>/dev/null) || bbox=""
  [[ -n $bbox ]] || return 0
  local top=${bbox#*,}
  printf '%s\n' "${top%% *}"
}

assert_entry_top() {
  local description="$1" logo_w="$2" logo_h="$3" min="$4" max="$5"
  local y
  if ! y=$(entry_top_y "$logo_w" "$logo_h"); then
    fail "$description" "preview command failed for a ${logo_w}x${logo_h} logo"
  fi
  if [[ -n $y ]] && (( y >= min && y <= max )); then
    pass "$description (entry top y=$y)"
  else
    fail "$description" "entry top y='${y:-none}', expected $min..$max"
  fi
}

# A full-screen logo pushes the field below the window; the clamp keeps it 40px
# above the bottom edge (1080 - 48 - 40 = 992) instead of off-screen at 1120.
assert_entry_top "full-screen logo keeps the entry field on-screen" 1920 1080 985 1000

# A small logo leaves the field below the logo, unclamped (440 + 200 + 40 = 680).
assert_entry_top "small logo leaves the entry field below the logo" 200 200 675 690

# The boot script applies the same clamp so the real unlock screen matches.
script="$ROOT/default/plymouth/omarchy.script"
grep -q 'entry_max_y = Window.GetHeight() - entry.image.GetHeight() - 40;' "$script" \
  || fail "boot script clamps the entry field to the window"
grep -q 'if (entry.y > entry_max_y) entry.y = entry_max_y;' "$script" \
  || fail "boot script applies the entry field clamp"
pass "boot script clamps the entry field to the window"
