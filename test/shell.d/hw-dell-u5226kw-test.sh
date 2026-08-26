#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

drm_path="$test_tmp/drm"

write_edid() {
  # Bytes 8-11 = manufacturer ID + product code. 10:ac:9e:43 is the Dell
  # U5226KW; the rest of the header is irrelevant to the detector.
  rm -rf "$drm_path"
  mkdir -p "$drm_path"

  local connector bytes
  while (( $# )); do
    connector="$1"
    bytes="$2"
    mkdir -p "$drm_path/card0-$connector"
    printf '\x00\x00\x00\x00\x00\x00\x00\x00'"$bytes" >"$drm_path/card0-$connector/edid"
    shift 2
  done
}

detect() {
  OMARCHY_DRM_PATH="$drm_path" "$ROOT/bin/omarchy-hw-dell-u5226kw"
}

write_edid DP-1 '\x10\xac\x9e\x43'
detect || fail "a matching Dell U5226KW EDID is detected"
pass "detects a connected Dell U5226KW"

write_edid DP-1 '\x10\xac\x00\x00'
if detect; then
  fail "a different Dell product code is not mistaken for the U5226KW"
fi
pass "ignores a non-matching product code from the same manufacturer"

write_edid
if detect; then
  fail "an empty DRM tree has no display to match"
fi
pass "handles an empty DRM tree"

write_edid DP-1 '\x10\xac\x00\x00' DP-2 '\x10\xac\x9e\x43'
detect || fail "the match is found alongside an unrelated connected display"
pass "finds the match alongside another connected display"
