if ! declare -F use_omarchy_pacman_config >/dev/null; then
  source "${OMARCHY_INSTALL:-${BASH_SOURCE[0]%/*}/..}/helpers/pacman.sh"
fi

# Configure pacman
use_omarchy_pacman_config

if lspci -nn | grep -q "106b:180[12]"; then
  cat <<EOF | sudo tee -a /etc/pacman.conf >/dev/null

[arch-mact2]
Server = https://github.com/NoaHimesaka1873/arch-mact2-mirror/releases/download/release
SigLevel = Never
EOF
fi
