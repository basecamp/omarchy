echo "Install framework-system for Framework Desktop ARGB fan control"

if omarchy-hw-framework-desktop; then
  omarchy-pkg-add framework-system

  # The passwordless sudo rule is shipped by the omarchy-settings package
  # (etc/sudoers.d/omarchy-framework-tool). Clean up the legacy filename
  # used by the initial implementation if it exists, and make sure the
  # canonical rule is present for installs that have not updated the
  # omarchy-settings package yet.
  if [[ -f /etc/sudoers.d/framework-tool ]]; then
    sudo rm /etc/sudoers.d/framework-tool
  fi

  if [[ ! -f /etc/sudoers.d/omarchy-framework-tool ]]; then
    echo "%wheel ALL=(root) NOPASSWD: /usr/bin/omarchy-framework-tool-rgb" | sudo tee /etc/sudoers.d/omarchy-framework-tool > /dev/null
    sudo chmod 440 /etc/sudoers.d/omarchy-framework-tool
  fi
fi
