OMARCHY_DESCRIPTION="Timezone Update Permissions"

omarchy_install() {
  # Ensure timezone can be updated without needing to sudo
  sudo tee /etc/sudoers.d/omarchy-tzupdate >/dev/null <<EOF
%wheel ALL=(root) NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl
EOF
  sudo chmod 0440 /etc/sudoers.d/omarchy-tzupdate
}

omarchy_verify() {
  sudo test -f /etc/sudoers.d/omarchy-tzupdate || add_error "Timezone sudoers file missing"

  if sudo test -f /etc/sudoers.d/omarchy-tzupdate; then
    local perms=$(sudo stat -c %a /etc/sudoers.d/omarchy-tzupdate)
    [[ "$perms" == "440" ]] || add_error "Sudoers file has incorrect permissions: $perms (should be 440)"

    sudo grep -q "NOPASSWD: /usr/bin/tzupdate, /usr/bin/timedatectl" /etc/sudoers.d/omarchy-tzupdate || add_error "Timezone sudoers rule not configured"
  fi
}
