# Hardware-specific pacman repository extensions that must survive the final
# pacman.conf restore.
if lspci -nn | grep -q "106b:180[12]"; then
  if ! grep -q '^\[arch-mact2\]' /etc/pacman.conf; then
    cat >> /etc/pacman.conf <<'EOF'

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
  fi
fi
