echo "Install Omarchy's bundled extensions into Google Chrome"

# Chrome ignores the --load-extension switch the flags file relies on, so
# installs made before this shipped have Chromium's three extensions and none of
# Chrome's. omarchy-install-chrome-extensions is idempotent.
omarchy-cmd-present google-chrome-stable || exit 0

omarchy-install-chrome-extensions
