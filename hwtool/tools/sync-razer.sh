#!/bin/bash
#
# tools/sync-razer.sh
#
# Regenerate the match_value array in rules/peripheral-razer.rule from
# OpenRazer's published JSON API.
#
# The OpenRazer site exposes a stable static endpoint:
#   https://openrazer.github.io/api/devices.json
#
# This is preferred over scraping the YAML or kernel headers because:
#  - It's the published API the upstream maintainers tell other tools to use
#  - Plain JSON, so jq alone parses it (no yq, no python+pyyaml)
#  - It's always the latest content from the main branch
#
# Output: emits the match_value=( ... ) block to stdout. Review the diff
# before pasting into rules/peripheral-razer.rule.

set -euo pipefail

DEVICES_URL='https://openrazer.github.io/api/devices.json'

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: '$1' is required" >&2
    exit 1
  }
}

main() {
  require curl
  require jq

  # Pull primary "vid:pid" plus every entry in alias_ids[],
  # lowercase, dedupe, sort.
  local pids
  pids=$(curl -fsSL "$DEVICES_URL" \
    | jq -r '.[] | (.vid + ":" + .pid), (.alias_ids[]?)' \
    | tr 'A-F' 'a-f' \
    | sort -u)

  local count
  count=$(printf '%s\n' "$pids" | wc -l)

  local today
  today=$(date -u +%Y-%m-%d)

  echo "# Generated from $DEVICES_URL"
  echo "# Regenerate with: tools/sync-razer.sh > /tmp/razer-pids.txt"
  echo "# then paste the match_value=(...) block into rules/peripheral-razer.rule"
  echo "# Last sync: $today  (UTC)"
  echo "# $count PIDs (primary + alias_ids), sorted, deduplicated"
  echo "match_value=("
  # Seven PIDs per line, indented 4, single-space separated. Width:
  # 4 (indent) + 7*9 (PIDs) + 6 (separators) = 73 chars, fits in 80
  # columns even with a one-char diff prefix.
  local idx=0 line=""
  while IFS= read -r pid; do
    if (( idx % 7 == 0 )); then
      [[ -n "$line" ]] && printf '%s\n' "$line"
      line="    $pid"
    else
      line+=" $pid"
    fi
    idx=$((idx + 1))
  done <<<"$pids"
  [[ -n "$line" ]] && printf '%s\n' "$line"
  echo ")"
}

main "$@"
