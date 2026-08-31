# Chromium ships in the base packages, so it never goes through
# omarchy-install-browser, and fresh installs mark every migration as already
# applied. Without this, the bundled extensions load but have no native
# messaging host to talk to.
mkdir -p ~/.config/chromium
touch ~/.config/chromium/'EULA Accepted'
omarchy-install-chromium-copy-url
omarchy-install-chromium-ytdlp
