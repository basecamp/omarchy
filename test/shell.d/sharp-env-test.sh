#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

bootstrap="$ROOT/default/bash/env-bootstrap"

if ! sharp_ignore=$(env -u SHARP_IGNORE_GLOBAL_LIBVIPS -u SHARP_FORCE_GLOBAL_LIBVIPS bash -c 'source "$1" || exit 1; printf "%s" "$SHARP_IGNORE_GLOBAL_LIBVIPS"' bash "$bootstrap"); then
  fail "env bootstrap ignores the Omarchy-provided libvips for sharp" "failed to source: $bootstrap"
fi
[[ $sharp_ignore == "1" ]] || fail "env bootstrap ignores the Omarchy-provided libvips for sharp" "actual: $sharp_ignore"
pass "env bootstrap ignores the Omarchy-provided libvips for sharp"

if ! sharp_ignore=$(env -u SHARP_FORCE_GLOBAL_LIBVIPS SHARP_IGNORE_GLOBAL_LIBVIPS= bash -c 'source "$1" || exit 1; printf "<%s>" "$SHARP_IGNORE_GLOBAL_LIBVIPS"' bash "$bootstrap"); then
  fail "env bootstrap preserves an explicit sharp system-libvips opt-in" "failed to source: $bootstrap"
fi
[[ $sharp_ignore == "<>" ]] || fail "env bootstrap preserves an explicit sharp system-libvips opt-in" "actual: $sharp_ignore"
pass "env bootstrap preserves an explicit sharp system-libvips opt-in"

if ! sharp_env=$(env -u SHARP_IGNORE_GLOBAL_LIBVIPS SHARP_FORCE_GLOBAL_LIBVIPS=1 bash -c 'source "$1" || exit 1; printf "%s:%s" "$SHARP_FORCE_GLOBAL_LIBVIPS" "${SHARP_IGNORE_GLOBAL_LIBVIPS+set}"' bash "$bootstrap"); then
  fail "env bootstrap preserves sharp's force-global override" "failed to source: $bootstrap"
fi
[[ $sharp_env == "1:" ]] || fail "env bootstrap preserves sharp's force-global override" "actual: $sharp_env"
pass "env bootstrap preserves sharp's force-global override"
