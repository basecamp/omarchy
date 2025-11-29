# Skip for online installs - preflight/pacman.sh already handled this
# Skip for ARM - no T2 Mac repo needed (x86-only)
# This is only needed for offline x86 installs (ISO-based, including T2 Macs)
if [[ -n ${OMARCHY_ONLINE_INSTALL:-} ]] || [[ -n "$OMARCHY_ARM" ]]; then
  return 0
fi

# Configure pacman
sudo cp -f ~/.local/share/omarchy/default/pacman/pacman.conf /etc/pacman.conf
sudo cp -f ~/.local/share/omarchy/default/pacman/mirrorlist /etc/pacman.d/mirrorlist

if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
