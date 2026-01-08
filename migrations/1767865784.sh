echo "Ensure Chromium is able to start on first run after new ISO install"

# FIXME: Find out why this is here before chromium has even been started!
rm -rf ~/.config/chromium/SingletonLock
