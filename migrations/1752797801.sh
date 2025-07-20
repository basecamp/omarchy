echo "fix omarchy seamless login service"
sed -i 's/Restart=always/Restart=on-success/' /etc/systemd/system/omarchy-seamless-login.service
sudo systemctl daemon-reload
