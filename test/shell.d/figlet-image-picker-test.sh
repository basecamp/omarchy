#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
preview_dir="$tmp_dir/previews"
mkdir -p "$stub_bin" "$preview_dir"

cat >"$preview_dir/ANSI_SHADOW.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50">
  <rect width="100" height="50" fill="black"/>
</svg>
SVG

cat >"$stub_bin/omarchy-shell" <<'SH'
#!/bin/bash

[[ $1 == "image-selector" && $2 == "openFitted" ]] || exit 1
printf '%s' "$4" | base64 -d >"$OMARCHY_TEST_IMAGE_ROWS"
printf '%s\n' "$(cut -f1 "$OMARCHY_TEST_IMAGE_ROWS" | head -n 1)" >"$6"
touch "$7"
printf '%s\n' "ok"
SH

chmod +x "$stub_bin/omarchy-shell"

export PATH="$stub_bin:$ROOT/bin:$PATH"
export XDG_CACHE_HOME="$tmp_dir/cache"
export OMARCHY_TEST_IMAGE_ROWS="$tmp_dir/image-rows"

selection=$(omarchy-menu-images --print-name --no-thumbnails --fit "$preview_dir")

[[ $selection == "ANSI_SHADOW" ]] ||
  fail "image selector returns the selected FIGlet preview name"
pass "image selector returns the selected FIGlet preview name"
[[ $(<"$OMARCHY_TEST_IMAGE_ROWS") == "$preview_dir/ANSI_SHADOW.svg" ]] ||
  fail "image selector sends SVG previews without thumbnails"
pass "image selector sends SVG previews without thumbnails"
