echo "Backfill yt-dlp and Copy URL native messaging hosts for Brave Origin profiles"

# The yt-dlp and Copy URL native messaging host installers omitted Brave
# Origin's profile roots from their browser_dirs list, so both extensions
# loaded but silently did nothing on Brave Origin — chrome.runtime.sendNativeMessage
# failed with no manifest in the profile's NativeMessagingHosts directory. The
# installers now include Brave Origin; re-run them to backfill the manifests
# for users who already installed Brave Origin through Omarchy before the fix.
#
# Only users who opted into an extension before this fix have anything to
# backfill: the installers write their manifests into every Chromium-family
# profile root unconditionally, so re-running them blind would plant native
# messaging hosts in profiles that never asked for one. Treat an existing
# manifest in any known profile root as opt-in evidence, per extension.

profile_roots=(
  "$HOME/.config/chromium"
  "$HOME/.config/google-chrome"
  "$HOME/.config/google-chrome-beta"
  "$HOME/.config/google-chrome-unstable"
  "$HOME/.config/BraveSoftware/Brave-Browser"
  "$HOME/.config/BraveSoftware/Brave-Browser-Beta"
  "$HOME/.config/BraveSoftware/Brave-Browser-Nightly"
  "$HOME/.config/microsoft-edge"
  "$HOME/.config/microsoft-edge-dev"
)

run_ytdlp=false
run_copy_url=false
for dir in "${profile_roots[@]}"; do
  if [[ -f $dir/NativeMessagingHosts/com.omarchy.ytdlp.json ]]; then
    run_ytdlp=true
  fi
  if [[ -f $dir/NativeMessagingHosts/com.omarchy.copy_url.json ]]; then
    run_copy_url=true
  fi
done

if [[ $run_ytdlp == true ]]; then
  omarchy-install-chromium-ytdlp
fi

if [[ $run_copy_url == true ]]; then
  omarchy-install-chromium-copy-url
fi
