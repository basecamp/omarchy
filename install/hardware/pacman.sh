# Hardware-specific pacman repository extensions that must survive the final
# pacman.conf restore.

pacman_conf=${OMARCHY_PACMAN_CONF:-/etc/pacman.conf}

# Touchscreen support on IPTS-era Surfaces installs the linux-surface kernel
# (see surface-touch.sh); its repository has to be restored here too or future
# kernel updates would fail. Gate on the package instead of the hardware so a
# Secure Boot skip never leaves a third-party repository without its key.
if omarchy-hw-surface && omarchy-pkg-present linux-surface && ! grep -q '^\[linux-surface\]' "$pacman_conf"; then
  cat >> "$pacman_conf" <<'EOF'

[linux-surface]
Server = https://pkg.surfacelinux.com/arch/
EOF
fi

if lspci -nn | grep "106b:180[12]" >/dev/null; then
  if ! grep -q '^\[arch-mact2\]' "$pacman_conf"; then
    cat >> "$pacman_conf" <<'EOF'

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
  fi
fi
