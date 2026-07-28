echo "Register the native messaging hosts for the bundled Chromium extensions"

# Fresh installs stamped 1780517689 and 1784763917 as applied without running
# them, so the bundled extensions loaded with no host to talk to.
omarchy-install-chromium-copy-url
omarchy-install-chromium-ytdlp
