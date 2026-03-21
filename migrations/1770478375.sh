echo "Install framework-system and configure sudoers for Framework Desktop ARGB fan control"

if omarchy-hw-framework-desktop; then
  omarchy-pkg-add framework-system

  if [[ ! -f /etc/sudoers.d/framework-tool ]]; then
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/framework_tool" | sudo tee /etc/sudoers.d/framework-tool > /dev/null
    sudo chmod 440 /etc/sudoers.d/framework-tool
  fi
fi
