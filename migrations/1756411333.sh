echo "Use new Omarchy mirror as default"

sudo tee /etc/pacman.d/mirrorlist >/dev/null <<'EOF'
Server = https://mirror.omarchy.org/$repo/os/$arch
Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch
Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch
EOF
