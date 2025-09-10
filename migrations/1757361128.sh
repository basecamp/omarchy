echo "Enable mDNS resolution for existing Avahi installations"

if systemctl is-enabled avahi-daemon.service >/dev/null 2>&1; then
  if ! grep -q "mdns_minimal" /etc/nsswitch.conf; then
    sudo sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve [!UNAVAIL=return] files myhostname dns/' /etc/nsswitch.conf
  fi
fi