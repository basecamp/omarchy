#!/bin/bash

set -euo pipefail

data=$1
registry=$2

jq -e '
  keys == ["authority", "capabilities", "schemaVersion"] and
  .schemaVersion == 1 and
  .authority == "org.omarchy.plugin-security" and
  [.capabilities[].id] == ["storage.private", "notifications.send", "audio.play-cue"] and
  all(.capabilities[];
    .version == 1 and
    .kind == "builtin" and
    (.operations | type == "array" and length > 0) and
    keys == ["gesture", "id", "kind", "operations", "provider", "revocation", "scope", "version"] and
    (.provider | type == "string" and length > 0))
' "$data" >/dev/null

mapfile -t data_capabilities < <(jq -r '.capabilities[].id' "$data")
mapfile -t registered_capabilities < <("$registry" --list-capabilities)
if (( ${#data_capabilities[@]} != ${#registered_capabilities[@]} )); then
  echo "built-in policy data and capability registry differ" >&2
  exit 1
fi
for (( index = 0; index < ${#data_capabilities[@]}; ++index )); do
  if [[ ${data_capabilities[index]} != ${registered_capabilities[index]} ]]; then
    echo "built-in policy data and capability registry differ" >&2
    exit 1
  fi
done

if grep -F 'service.fake-status' "$data" >/dev/null; then
  echo "test-only fake provider leaked into built-in policy data" >&2
  exit 1
fi
