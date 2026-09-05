echo "Repair the Copy URL shortcut for Brave Origin profiles"

# The repair in 1786643346 walked every Chromium-family profile root except
# Brave Origin's, which Omarchy has installed since before the extension id
# was pinned. Those profiles still bind Alt+Shift+L to a ghost id. The
# original now covers them and is idempotent, so re-running it is safe.
source "$OMARCHY_PATH/migrations/1786643346.sh"
