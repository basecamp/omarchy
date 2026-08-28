#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

export PATH="$ROOT/bin:$PATH"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Stub sudo so the installer can write into our temp tree without privilege,
# and omarchy-cmd-present so setup_zen_preferences sees jq as available.
mock_bin="$TMPDIR/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$mock_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ ${1:-} == "jq" ]]
SH

chmod +x "$mock_bin"/*

distribution="$TMPDIR/zen-browser-bin/distribution"

# Simulate the policies the zen-browser-bin AUR package ships: DisableAppUpdate
# and DefaultSerialGuardSetting. The fix must merge Omarchy's Preferences on
# top of these, not overwrite them.
mkdir -p "$distribution"
cat >"$distribution/policies.json" <<'JSON'
{
  "policies": {
    "DisableAppUpdate": true,
    "DefaultSerialGuardSetting": 3
  }
}
JSON

PATH="$mock_bin:$PATH" OMARCHY_PATH="$ROOT" bash -c '
  source "$1/bin/omarchy-install-browser"
  setup_zen_preferences "$2"
' bash "$ROOT" "$distribution"

[[ -f $distribution/policies.json ]] || fail "zen preferences wrote policies.json"

jq -e '
  .policies.DisableAppUpdate == true and
  .policies.DefaultSerialGuardSetting == 3 and
  (.policies.Preferences."apz.overscroll.enabled".Value == true) and
  (.policies.Preferences."media.ffmpeg.vaapi.enabled".Value == true) and
  (.policies.Preferences."widget.wayland.fractional-scale.enabled".Value == true)
' "$distribution/policies.json" >/dev/null ||
  fail "zen preferences preserve package policies and add Omarchy Preferences" \
    "$(jq -c . "$distribution/policies.json")"
pass "zen preferences preserve package policies and add Omarchy Preferences"

# Without a pre-existing package policies.json, the installer falls back to a
# plain copy of Omarchy's policies.
fresh_distribution="$TMPDIR/zen-browser-bin-fresh/distribution"
PATH="$mock_bin:$PATH" OMARCHY_PATH="$ROOT" bash -c '
  source "$1/bin/omarchy-install-browser"
  setup_zen_preferences "$2"
' bash "$ROOT" "$fresh_distribution"

jq -e '.policies.Preferences."apz.overscroll.enabled".Value == true' \
  "$fresh_distribution/policies.json" >/dev/null ||
  fail "zen preferences fall back to a plain copy without package policies"
pass "zen preferences fall back to a plain copy without package policies"

# The installer must target the path Zen actually reads from, not the
# /opt/zen-browser path from the original report.
grep -q "zen-browser-bin/distribution" "$ROOT/bin/omarchy-install-browser" ||
  fail "zen installer targets the zen-browser-bin install path"
if grep -q "zen-browser/distribution" "$ROOT/bin/omarchy-install-browser"; then
  fail "zen installer still references the unused zen-browser path"
fi
pass "zen installer targets the path Zen reads from"
