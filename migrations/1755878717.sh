echo "Ensure Docker DNS requests are not blocked by ufw firewall"

sudo ufw disable
sudo ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment 'allow-docker-dns'
sudo ufw enable
