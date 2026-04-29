abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Must be an Arch distro
if [[ ! -f /etc/arch-release ]]; then
  abort "Vanilla Arch"
fi

# Must not be an Arch derivative distro
for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
  if [[ -f $marker ]]; then
    abort "Vanilla Arch"
  fi
done

# Must not be running as root
if (( EUID == 0 )); then
  abort "Running as root (not user)"
fi

# Must have secure boot disabled
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
  abort "Secure Boot disabled"
fi

# Must not have Gnome or KDE already install
if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
  abort "Fresh + Vanilla Arch"
fi

# Must have limine installed (skip on ARM/non-Limine systems - will be installed during setup or using alternative bootloader)
if [ -z "$OMARCHY_ARM" ] && [ -z "$ASAHI_ALARM" ] && [ -z "$OMARCHY_SKIP_LIMINE" ]; then
  command -v limine &>/dev/null || abort "Limine bootloader"
fi

# Must have btrfs root filesystem (skip on ARM/Asahi - uses ext4, can't use btrfs)
if [ -z "$OMARCHY_ARM" ] && [ -z "$ASAHI_ALARM" ]; then
  [[ $(findmnt -n -o FSTYPE /) = "btrfs" ]] || abort "Btrfs root filesystem"
fi

# Cleared all guards
if [[ "$OMARCHY_RETRY_INSTALL" == "true" ]]; then
  echo
  gum style "Guards: OK"
else
  echo
  echo "Guards: OK"
fi
