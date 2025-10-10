# Add 1password extension to Chromium
sudo mkdir -p /etc/chromium/policies/managed/
sudo cp $OMARCHY_PATH/default/chromium/policies/managed/onepassword.json /etc/chromium/policies/managed/onepassword.json
sudo chmod 644 /etc/chromium/policies/managed/onepassword.json

# Add 1password extension to future Brave installs
sudo mkdir -p /etc/brave/policies/managed/
sudo cp $OMARCHY_PATH/default/brave/policies/managed/onepassword.json /etc/brave/policies/managed/onepassword.json
sudo chmod 644 /etc/brave/policies/managed/onepassword.json
