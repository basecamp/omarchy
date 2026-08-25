echo "Retry the Copy URL shortcut repair after install-time migration stamping"

# 1786643346 is already stamped complete on fresh installs, so a Chromium
# profile that arrived later via sync never got the repair. This covers
# existing users on update. The same command is also invoked from first-run,
# login notify, and browser launch, which are not migration-stamped.
omarchy-cmd-repair-chromium-copy-url --prompt
