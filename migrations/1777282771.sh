echo "Allow Docker DNS from Docker's 192.168 address pool"

if omarchy-cmd-present ufw; then
  sudo ufw allow in proto udp from 192.168.0.0/16 to 172.17.0.1 port 53 comment 'allow-docker-dns'
fi
