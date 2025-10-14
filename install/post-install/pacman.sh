# Configure pacman

# Skip for online installs - preflight/pacman.sh already handled this
if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]]; then
  return 0
fi

# Configure pacman for ARM
if [[ -n "${OMARCHY_ARM:-}" ]]; then
  sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf.arm /etc/pacman.conf
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.arm /etc/pacman.d/mirrorlist
  sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist.asahi-alarm /etc/pacman.d/mirrorlist.asahi-alarm
  return 0
fi

# Configure pacman for x86 offline installs
sudo cp -f ~/.local/share/omarchy/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf /etc/pacman.conf
sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable} /etc/pacman.d/mirrorlist

# Add T2 Mac repository if needed (x86 only)
if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
