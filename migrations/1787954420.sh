echo "Install Omafox for existing Firefox and Zen users"

firefox_installed=false
zen_installed=false

omarchy-pkg-present firefox && firefox_installed=true
omarchy-pkg-present zen-browser-bin && zen_installed=true

if [[ $firefox_installed == "true" || $zen_installed == "true" ]]; then
  source "$OMARCHY_PATH/install/helpers/browser-policy.sh"

  omarchy-pkg-aur-add omafox

  if [[ $firefox_installed == "true" ]]; then
    browser_policy_ensure_firefox_omafox_policy /usr/lib/firefox/distribution
  fi

  if [[ $zen_installed == "true" ]]; then
    browser_policy_ensure_firefox_omafox_policy /opt/zen-browser/distribution
  fi

  omafox setup
fi
