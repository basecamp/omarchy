echo "Register the Chromium native messaging hosts for Brave Origin"

# Brave Origin's profile root was missing from the host installers, so its
# NativeMessagingHosts directory was never written and Copy URL and Download
# Video did nothing there. Both installers are idempotent, so re-running them
# registers the hosts for Brave Origin and leaves every other profile as is.
omarchy-install-chromium-copy-url
omarchy-install-chromium-ytdlp
