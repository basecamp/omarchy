echo "Repair the Copy URL shortcut for profiles that predate its pinned extension id"

# Fresh installs stamp every shipped migration complete, so a Chromium profile
# that arrives later via sync never runs this file. Keep it for unstamped
# upgrades; omarchy-cmd-repair-chromium-copy-url is also invoked from first-run,
# login notify, and browser launch, which are not migration-stamped.
omarchy-cmd-repair-chromium-copy-url --prompt
