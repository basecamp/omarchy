echo "Discover Windows PCs in Files"

omarchy-pkg-add gvfs-wsdd

sudo ufw allow in proto udp from 10.0.0.0/8 port 3702 comment 'ws-discovery'
sudo ufw allow in proto udp from 172.16.0.0/12 port 3702 comment 'ws-discovery'
sudo ufw allow in proto udp from 192.168.0.0/16 port 3702 comment 'ws-discovery'
sudo ufw allow in proto udp from fe80::/10 port 3702 comment 'ws-discovery-ipv6'
