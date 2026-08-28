#!/bin/bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command jq

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

distribution_dir="$test_dir/distribution"
mkdir -p "$distribution_dir"

sudo() {
  "$@"
}

# Load the real helper without running the installer.
source <(sed '/^case \$1 in/,$d' "$ROOT/bin/omarchy-install-browser")

cat >"$distribution_dir/policies.json" <<'JSON'
{
  "policies": {
    "DisableAppUpdate": true,
    "Preferences": {
      "existing.preference": {
        "Value": true
      },
      "media.ffmpeg.vaapi.enabled": {
        "Value": false
      }
    }
  }
}
JSON

OMARCHY_PATH="$ROOT" setup_zen_preferences "$distribution_dir"

jq -e '
  .policies.DisableAppUpdate == true and
  .policies.Preferences["existing.preference"].Value == true and
  .policies.Preferences["media.ffmpeg.vaapi.enabled"].Value == false and
  .policies.Preferences["media.hardware-video-decoding.force-enabled"].Value == true
' "$distribution_dir/policies.json" >/dev/null || fail "Zen setup preserves existing policies and adds Omarchy policies"

grep -Fq '/opt/zen-browser-bin/distribution' "$ROOT/bin/omarchy-install-browser" ||
  fail "Zen policies use the browser installation directory"
grep -Fqx '  setup_zen_preferences' "$ROOT/bin/omarchy-install-browser" ||
  fail "Zen install sets up browser policies"

pass "Zen setup merges policies in the browser installation directory"
