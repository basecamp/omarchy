echo "Installing Ghostty terminal for ARM VMs..."

# Check if Ghostty is already installed
if command -v ghostty &>/dev/null; then
  echo "Ghostty already installed, skipping"
  return 0
fi

# Install official repo dependencies
echo "Installing dependencies..."
sudo pacman -S --needed --noconfirm blueprint-compiler git base-devel

# Install pandoc-bin from AUR (provides pandoc-cli)
echo "Installing pandoc-bin from AUR..."
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" pandoc-bin

# Install Zig 0.15.2 (required for Ghostty build)
if ! command -v zig &>/dev/null || ! zig version | grep -q "0.15.2"; then
  echo "Installing Zig 0.15.2..."
  cd /tmp
  curl -L -O https://ziglang.org/download/0.15.2/zig-aarch64-linux-0.15.2.tar.xz
  tar -xf zig-aarch64-linux-0.15.2.tar.xz
  sudo mv zig-aarch64-linux-0.15.2 /usr/local/
  sudo ln -sf /usr/local/zig-aarch64-linux-0.15.2/zig /usr/local/bin/zig
  rm -f zig-aarch64-linux-0.15.2.tar.xz

  # Verify installation
  if zig version | grep -q "0.15.2"; then
    echo "Zig 0.15.2 installed successfully"
  else
    echo "Warning: Zig installation may have failed"
  fi
else
  echo "Zig 0.15.2 already installed, skipping"
fi

# Install ghostty-git from AUR
echo "Installing ghostty-git from AUR..."
"$OMARCHY_PATH/bin/omarchy-aur-install" --makepkg-flags="--needed" ghostty-git

# Create wrapper script with runtime VM detection
echo "Creating Ghostty wrapper script with automatic VM detection..."
mkdir -p ~/.local/share/omarchy/bin

cat > ~/.local/share/omarchy/bin/ghostty << 'EOF'
#!/bin/bash
# Ghostty wrapper - Auto-detects VM and uses software rendering when needed

# Check if running in a VM
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt)
  if [[ "$virt_type" != "none" ]]; then
    # Running in a VM - enable software rendering
    export GSK_RENDERER=cairo
    export LIBGL_ALWAYS_SOFTWARE=1
  fi
fi

# Execute the real ghostty binary
exec /usr/bin/ghostty "$@"
EOF

chmod +x ~/.local/share/omarchy/bin/ghostty
echo "Wrapper script created at ~/.local/share/omarchy/bin/ghostty"

# Create desktop file override to use wrapper
echo "Creating desktop file override..."
mkdir -p ~/.local/share/applications

cat > ~/.local/share/applications/com.mitchellh.ghostty.desktop << 'EOF'
[Desktop Entry]
Version=1.0
Name=Ghostty
Type=Application
Comment=A terminal emulator
TryExec=$HOME/.local/share/omarchy/bin/ghostty
Exec=$HOME/.local/share/omarchy/bin/ghostty --gtk-single-instance=true
Icon=com.mitchellh.ghostty
Categories=System;TerminalEmulator;
Keywords=terminal;tty;pty;
StartupNotify=true
StartupWMClass=com.mitchellh.ghostty
Terminal=false
Actions=new-window;
X-GNOME-UsesNotifications=true
X-TerminalArgExec=-e
X-TerminalArgTitle=--title=
X-TerminalArgAppId=--class=
X-TerminalArgDir=--working-directory=
X-TerminalArgHold=--wait-after-command
DBusActivatable=true
X-KDE-Shortcuts=Ctrl+Alt+T

[Desktop Action new-window]
Name=New Window
Exec=$HOME/.local/share/omarchy/bin/ghostty --gtk-single-instance=true
EOF

# Update desktop database
update-desktop-database ~/.local/share/applications 2>/dev/null || true

echo "Ghostty installed successfully!"
echo "Note: Software rendering will automatically enable when running in a VM"
echo "To test: ghostty --version"
