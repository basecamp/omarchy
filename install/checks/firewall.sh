OMARCHY_DESCRIPTION="Firewall Configuration"

omarchy_verify() {
  # Check if UFW is enabled
  sudo ufw status | grep -q "Status: active" || add_error "UFW firewall not active"

  # Check if UFW service is enabled
  systemctl is-enabled ufw &>/dev/null || add_error "UFW service not enabled"

  # Check default policies - they're on one line as "Default: deny (incoming), allow (outgoing), deny (routed)"
  sudo ufw status verbose | grep -q "Default:.*deny (incoming)" || add_error "UFW default incoming policy not set to deny"
  sudo ufw status verbose | grep -q "Default:.*allow (outgoing)" || add_error "UFW default outgoing policy not set to allow"

  # Check specific rules are present
  sudo ufw status numbered | grep -q "53317/udp" || add_error "LocalSend UDP port 53317 not allowed"
  sudo ufw status numbered | grep -q "53317/tcp" || add_error "LocalSend TCP port 53317 not allowed"
  sudo ufw status numbered | grep -q "22/tcp" || add_error "SSH port 22 not allowed"

  # Check Docker DNS rule
  sudo ufw status numbered | grep -q "allow-docker-dns" || add_error "Docker DNS rule not configured"
}
