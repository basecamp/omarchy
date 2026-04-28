#!/bin/bash

# Update omarchy-snapshot to include /home exclusion warning
# See: https://github.com/basecamp/omarchy/issues/5361

echo "Updating omarchy-snapshot with /home exclusion warning..."

SOURCE_SNAPSHOT="$OMARCHY_PATH/bin/omarchy-snapshot"
TARGET_SNAPSHOT="/usr/local/bin/omarchy-snapshot"

if [[ ! -f "$SOURCE_SNAPSHOT" ]]; then
  echo "Error: updated snapshot script not found at $SOURCE_SNAPSHOT"
  exit 1
fi

if [[ ! -d "$(dirname "$TARGET_SNAPSHOT")" ]]; then
  echo "Error: target directory $(dirname "$TARGET_SNAPSHOT") does not exist"
  exit 1
fi

if ! sudo install -m 0755 "$SOURCE_SNAPSHOT" "$TARGET_SNAPSHOT" 2>/dev/null; then
  echo "Error: failed to update $TARGET_SNAPSHOT"
  exit 1
fi

if ! grep -q "will NOT be affected" "$TARGET_SNAPSHOT" 2>/dev/null; then
  echo "Error: $TARGET_SNAPSHOT was updated, but the /home exclusion warning is still missing"
  exit 1
fi

echo ""
echo "✓ Updated omarchy-snapshot with /home warning"