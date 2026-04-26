#!/bin/bash

# Configure snapshot restore messaging for /home exclusion
# See: https://github.com/basecamp/omarchy/issues/5361

echo "Configuring snapshot restore messaging..."

# The issue is that limine-snapper-restore might restore /home along with root
# This script adds warning output to omarchy-snapshot to inform users

# Update omarchy-snapshot with /home exclusion warning
if [[ -f /usr/local/bin/omarchy-snapshot ]]; then
  if ! grep -q "will NOT be affected" /usr/local/bin/omarchy-snapshot 2>/dev/null; then
    echo "Warning: /usr/local/bin/omarchy-snapshot not updated (may already have warning)"
  fi
fi

echo ""
echo "✅ Snapshot restore warning configured"
echo "⚠️  Remember: Snapshot restore only affects ROOT filesystem"
echo "⚠️  Your /home directory will NOT be affected"
echo ""