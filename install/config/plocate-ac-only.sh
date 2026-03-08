sudo install -d /etc/systemd/system/plocate-updatedb.service.d
printf '%s\n' '[Unit]' 'ConditionACPower=true' | sudo tee /etc/systemd/system/plocate-updatedb.service.d/ac-only.conf >/dev/null
sudo systemctl daemon-reload
