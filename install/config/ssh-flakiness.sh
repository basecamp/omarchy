OMARCHY_DESCRIPTION="SSH Flakiness Fix"

omarchy_install() {
  # Solve common flakiness with SSH
  echo "net.ipv4.tcp_mtu_probing=1" | sudo tee -a /etc/sysctl.d/99-sysctl.conf
}

omarchy_verify() {
  [[ -f /etc/sysctl.d/99-sysctl.conf ]] || add_error "Sysctl config file missing"

  if [[ -f /etc/sysctl.d/99-sysctl.conf ]]; then
    grep -q "net.ipv4.tcp_mtu_probing=1" /etc/sysctl.d/99-sysctl.conf || add_error "TCP MTU probing not configured"
  fi
}
