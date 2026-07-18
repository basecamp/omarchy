#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

raw_command_checks=$(rg -l 'command -v' "$ROOT/bin" \
  | rg -v '/omarchy-(cmd-|pkg-|upgrade-to-quattro)' || true)
[[ -z $raw_command_checks ]] || fail "bin commands use command helpers" "$raw_command_checks"
pass "bin commands use command helpers"

raw_notifications=$(rg -l -P '^[[:space:]]*[^#[:space:]].*\bnotify-send\b' "$ROOT/bin" \
  | rg -v '/omarchy-notification-send$' || true)
[[ -z $raw_notifications ]] || fail "bin commands use the notification helper" "$raw_notifications"
pass "bin commands use the notification helper"
