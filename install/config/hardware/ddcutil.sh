#DDC/CI setup fot external monitor brightness control using ddcutil
sudo modprobe i2c-dev
echo 'i2c-dev' | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
sudo gpasswd -a "$USER" i2c

