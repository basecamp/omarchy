abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Must be an Arch distro
if [[ ! -f /etc/arch-release ]]; then
  abort "Vanilla Arch"
fi

# [omarchy] # Must not be an Arch derivative distro
# [omarchy] for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
# [omarchy]   if [[ -f "$marker" ]]; then
# [omarchy]     abort "Vanilla Arch"
# [omarchy]   fi
# [omarchy] done

# Must not be running as root
if [ "$EUID" -eq 0 ]; then
  abort "Running as root (not user)"
fi

# Must be x86 only to fully work
if [ "$(uname -m)" != "x86_64" ]; then
  abort "x86_64 CPU"
fi

# Must have secure boot disabled
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
  abort "Secure Boot disabled"
fi

# Must not have Gnome or KDE already install
if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
  abort "Fresh + Vanilla Arch"
fi

# [omarchy] # Must have limine installed
# [omarchy] command -v limine &>/dev/null || abort "Limine bootloader"

# Must have btrfs root filesystem
[ "$(findmnt -n -o FSTYPE /)" = "btrfs" ] || abort "Btrfs root filesystem" 

# Cleared all guards
echo "Guards: OK"
