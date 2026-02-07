# Install framework-system and configure passwordless sudo for framework_tool
# on Framework Desktop. Required because framework_tool reads SMBIOS data
# which needs root even for simple RGB fan control operations.

if omarchy-hw-framework-desktop; then
  omarchy-pkg-add framework-system

  if [[ ! -f /etc/sudoers.d/framework-tool ]]; then
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/framework_tool" | sudo tee /etc/sudoers.d/framework-tool > /dev/null
    sudo chmod 440 /etc/sudoers.d/framework-tool
  fi
fi
