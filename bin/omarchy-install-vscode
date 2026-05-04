#!/bin/bash

# Install VSCode and configure it to use the gnome-libsecret password store, not to update automatically, and to use the current Omarchy theme.

echo "Installing VSCode..."
omarchy-pkg-add visual-studio-code-bin

mkdir -p ~/.vscode ~/.config/Code/User

cat > ~/.vscode/argv.json << 'EOF'
// This configuration file allows you to pass permanent command line arguments to VS Code.
// Only a subset of arguments is currently supported to reduce the likelihood of breaking
// the installation.
//
// PLEASE DO NOT CHANGE WITHOUT UNDERSTANDING THE IMPACT
//
// NOTE: Changing this file requires a restart of VS Code.
{
  "password-store":"gnome-libsecret"
}
EOF

# Ensure VSC's own auto-update feature is turned off
printf '{\n  "update.mode": "none"\n}\n' > ~/.config/Code/User/settings.json

# Apply Omarchy theme to VSCode
omarchy-theme-set-vscode

setsid gtk-launch code
