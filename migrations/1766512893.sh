echo "Set make to use all cpus/cores during compilation"
sudo sed -i 's/^#MAKEFLAGS="-j2"/MAKEFLAGS="--jobs=$(nproc)"/' /etc/makepkg.conf
