#!/bin/bash

# Update omarchy-snapshot to include /home exclusion warning
# See: https://github.com/basecamp/omarchy/issues/5361

echo "Updating omarchy-snapshot with /home exclusion warning..."

TARGET_SNAPSHOT="/usr/local/bin/omarchy-snapshot"

# Update the installed omarchy-snapshot from the repo
if [[ -f "$TARGET_SNAPSHOT" ]] && [[ -f "$OMARCHY_PATH/bin/omarchy-snapshot" ]]; then
  if sudo install -m 0755 "$OMARCHY_PATH/bin/omarchy-snapshot" "$TARGET_SNAPSHOT" 2>/dev/null; then
    echo "Updated omarchy-snapshot with /home warning"
  else
    echo "Warning: Could not update omarchy-snapshot"
  fi
else
  echo "Warning: omarchy-snapshot not found at $TARGET_SNAPSHOT"
fi

echo ""
echo "Done: Snapshot restore will show /home exclusion warning"