echo "Separate printer discovery from root and print-filter access"

machine_marker="${OMARCHY_CUPS_MIGRATION_MARKER:-/var/lib/omarchy/migrations/1787815267}"

[[ ! -e $machine_marker ]] || exit 0

# CUPS-PDF accepts a job-controlled post-processing command in a backend that
# CUPS launches as root. Native application print-to-file support replaces it.
omarchy-pkg-drop cups-pdf

# system-config-printer uses this helper to request printer administration
# through Polkit now that the desktop user's wheel group is no longer @SYSTEM.
if omarchy-pkg-present cups; then
  omarchy-pkg-add cups-pk-helper
fi

cups_browsed_was_active=0
if systemctl is-active --quiet cups-browsed.service 2>/dev/null; then
  cups_browsed_was_active=1
  sudo systemctl stop cups-browsed.service
fi

if omarchy-pkg-present cups; then
  sudo env OMARCHY_PATH="$OMARCHY_PATH" \
    bash -euo pipefail "$OMARCHY_PATH/install/config/printing.sh"
  sudo systemctl daemon-reload
  sudo systemctl try-reload-or-restart cups.service
fi

if (( cups_browsed_was_active )) && omarchy-pkg-present cups-browsed; then
  sudo systemctl restart cups-browsed.service
fi

sudo install -Dm644 /dev/null "$machine_marker"
