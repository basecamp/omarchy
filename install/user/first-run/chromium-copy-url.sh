#!/bin/bash

# Repair a Copy URL shortcut registered under a path-derived extension id.
# Runs at first-run rather than as a migration because the finalizer marks all
# shipped migrations complete on a fresh install. The Chromium profile is not
# part of that install — it commonly arrives afterwards from sync or a restored
# ~/.config/chromium — so install-time stamping cannot satisfy this repair.
#
# Idempotent: no-ops when Preferences is missing or already points at the
# pinned id. A running browser is skipped and retried from login notify or
# the next browser launch, which are also not migration-stamped.

set -euo pipefail

omarchy-cmd-repair-chromium-copy-url
