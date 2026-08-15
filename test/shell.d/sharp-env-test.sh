#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

bootstrap="$ROOT/default/bash/env-bootstrap"

sharp_ignore=$(env -u SHARP_IGNORE_GLOBAL_LIBVIPS bash -c 'source "$1"; printf "%s" "$SHARP_IGNORE_GLOBAL_LIBVIPS"' bash "$bootstrap")
[[ $sharp_ignore == 1 ]] || fail "env bootstrap ignores the Omarchy-provided libvips for sharp" "actual: $sharp_ignore"
pass "env bootstrap ignores the Omarchy-provided libvips for sharp"

sharp_ignore=$(SHARP_IGNORE_GLOBAL_LIBVIPS= bash -c 'source "$1"; printf "<%s>" "$SHARP_IGNORE_GLOBAL_LIBVIPS"' bash "$bootstrap")
[[ $sharp_ignore == "<>" ]] || fail "env bootstrap preserves an explicit sharp system-libvips opt-in" "actual: $sharp_ignore"
pass "env bootstrap preserves an explicit sharp system-libvips opt-in"
