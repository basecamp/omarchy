abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Must be Fedora
if [[ ! -f /etc/fedora-release ]]; then
  abort "Fedora Linux"
fi

# Must be Fedora 44 or newer
fedora_version=$(rpm -E %fedora 2>/dev/null)
if (( fedora_version < 44 )); then
  abort "Fedora 44 or newer (found: Fedora $fedora_version)"
fi

# Must not be running as root
if (( EUID == 0 )); then
  abort "Running as root (not user)"
fi

# Must be x86_64
if [[ $(uname -m) != "x86_64" ]]; then
  abort "x86_64 CPU"
fi

# Must have secure boot disabled
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
  abort "Secure Boot disabled"
fi

# Must not have KDE already active (GNOME is fine as base — we'll add Hyprland)
if omarchy-pkg-present plasma-desktop 2>/dev/null; then
  abort "Fresh Fedora without KDE Plasma pre-installed"
fi

# Cleared all guards
echo "Guards: OK"
