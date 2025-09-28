OMARCHY_DESCRIPTION="Apple BCM4360 WiFi Driver"

should_run() {
  lspci -nnv | grep -A2 "14e4:43a0" | grep -q "106b:"
}

omarchy_install() {
  should_run || return 0

  echo "Apple BCM4360 detected"
  sudo pacman -S --noconfirm --needed broadcom-wl dkms linux-headers
}

omarchy_verify() {
  should_run || return 2

  omarchy-pkg-present broadcom-wl || add_error "Broadcom wireless driver not installed"
}
