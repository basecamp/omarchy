echo "Compile keyboard shortcuts for existing web apps"

# omarchy-webapp-shortcut is new in this release. Build the generated bindings
# file once so an existing web app that gains an X-Omarchy-Shortcut key is picked
# up without waiting for the next install or removal. Writes an empty stub and
# no-ops when no web app declares a shortcut, and is safe to run repeatedly.
# --no-reload: omarchy update reloads Hyprland once after all migrations run.
omarchy-webapp-shortcut sync --no-reload >/dev/null
