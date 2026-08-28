echo "Enable docker.service so Install > Docker DB containers survive reboot"

omarchy-cmd-present docker || exit 0

if systemctl is-enabled docker.service >/dev/null 2>&1; then
  exit 0
fi

# docker info talks to the socket, which is enough to start dockerd so inspect works.
sudo docker info >/dev/null 2>&1 || exit 0

found=0
for name in mysql8 postgres18 mariadb11 redis mongodb mssql; do
  if sudo docker inspect "$name" >/dev/null 2>&1; then
    found=1
    break
  fi
done

(( found )) || exit 0

sudo systemctl enable --now docker.service
