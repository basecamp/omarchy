OMARCHY_DESCRIPTION="SDDM Display Manager Configuration"

omarchy_install() {
  sudo mkdir -p /etc/sddm.conf.d

  if [ ! -f /etc/sddm.conf.d/autologin.conf ]; then
    cat <<EOF | sudo tee /etc/sddm.conf.d/autologin.conf
[Autologin]
User=$USER
Session=hyprland-uwsm

[Theme]
Current=breeze
EOF
  fi

  chrootable_systemctl_enable sddm.service
}

omarchy_verify() {
  [[ -d /etc/sddm.conf.d ]] || add_error "SDDM config directory missing"

  [[ -f /etc/sddm.conf.d/autologin.conf ]] || add_error "SDDM autologin config missing"

  if [[ -f /etc/sddm.conf.d/autologin.conf ]]; then
    grep -q "^User=$USER" /etc/sddm.conf.d/autologin.conf || add_error "SDDM autologin user not configured"

    grep -q "^Session=hyprland-uwsm" /etc/sddm.conf.d/autologin.conf || add_error "SDDM session not set to hyprland-uwsm"

    grep -q "^Current=breeze" /etc/sddm.conf.d/autologin.conf || add_warning "SDDM theme not set to breeze"
  fi

  systemctl is-enabled sddm.service &>/dev/null || add_error "SDDM service not enabled"
}
