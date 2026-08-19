echo "Backfill yt-dlp and Copy URL native messaging hosts for Brave Origin profiles"

# The yt-dlp and Copy URL native messaging host installers omitted Brave
# Origin's profile roots from their browser_dirs list, so both extensions
# loaded but silently did nothing on Brave Origin — chrome.runtime.sendNativeMessage
# failed with no manifest in the profile's NativeMessagingHosts directory. The
# installers now include Brave Origin; re-run them to backfill the manifests
# for users who already installed Brave Origin through Omarchy before the fix.
# Both installers are idempotent: they overwrite the same manifest in every
# Chromium-family profile root.

omarchy-install-chromium-ytdlp
omarchy-install-chromium-copy-url
