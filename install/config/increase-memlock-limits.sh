TARGET_USER="${SUDO_USER:-$USER}"
sudo mkdir -p /etc/security/limits.d
sudo tee /etc/security/limits.d/99-memlock.conf >/dev/null <<EOF
# Increase memlock limits for the primary user
# Required for: RPCS3, PCSX2, audio production (JACK), and other applications
# that need to lock large amounts of memory
${TARGET_USER} soft memlock unlimited
${TARGET_USER} hard memlock unlimited
EOF
