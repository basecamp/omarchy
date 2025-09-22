echo "Fix Tailscale split DNS compatibility by removing [!UNAVAIL=return] from nsswitch.conf"

if grep -q '\[!UNAVAIL=return\]' /etc/nsswitch.conf; then
  sudo sed -i 's/resolve \[!UNAVAIL=return\]/resolve/g' /etc/nsswitch.conf
fi