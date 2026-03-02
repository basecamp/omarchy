# Set up passwordless sudo for framework_tool on Framework Desktop.
# Required because framework_tool reads SMBIOS data which requires root,
# even for simple RGB control operations.

if omarchy-hw-framework-desktop; then
  if [[ ! -f /etc/sudoers.d/framework-tool ]]; then
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/framework_tool" | sudo tee /etc/sudoers.d/framework-tool > /dev/null
    sudo chmod 440 /etc/sudoers.d/framework-tool
  fi
fi
