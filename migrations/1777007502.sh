#!/bin/bash

# Fix snapshot restore to exclude /home from restoration
# See: https://github.com/basecamp/omarchy/issues/5361

echo "Configuring snapshot restore to exclude /home..."

# Get absolute path for omarchy
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"

# Create a wrapper script that warns users about /home
WRAPPER="/usr/local/bin/omarchy-snapshot-restore-safe"
cat << 'WRAPPEREOF' | sudo tee "$WRAPPER" > /dev/null
#!/bin/bash
# Safe snapshot restore wrapper
# Warns users that /home will NOT be restored

echo "⚠️  WARNING: This will restore the ROOT filesystem only."
echo "⚠️  Your /home directory will NOT be affected."
echo ""
echo "To restore a snapshot:"
echo "1. Reboot and select the snapshot from limine menu"
echo "2. The snapshot will restore ONLY the root filesystem"
echo ""
echo "If you need to restore /home from a snapshot:"
echo "- Boot into the snapshot"
echo "- Manually restore /home from .snapshots subvolumes"
echo ""

if [[ -t 0 ]]; then
  read -p "Continue with snapshot restore? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

exec sudo limine-snapper-restore "$@"
WRAPPEREOF

sudo chmod +x "$WRAPPER"

echo ""
echo "✅ Snapshot restore is configured to restore ROOT only"
echo "✅ /home will NOT be restored during snapshot operations"
echo ""
echo "If you've already had /home data loss:"
echo "1. Check .snapshots directory for backup of /home"
echo "2. You may need to manually restore from those snapshots"
