#!/bin/bash

# Skip if not virtualization and not VMware
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt)
  if [[ "$virt_type" != "vmware" ]]; then
    return 0
  fi
else
  return 0
fi

if command -v vmtoolsd &>/dev/null; then
  echo "VMware Tools already installed, skipping."
  return 0
fi

echo "Detected VMware, installing Open VM Tools..."

# Install build dependencies
echo "Installing build dependencies..."
sudo pacman -S --noconfirm --needed base-devel git autoconf automake libtool make \
  pkgconf glib2 glib2-devel libmspack rpcsvc-proto fuse3 procps-ng xmlsec gtkmm3

# Clone and build open-vm-tools
BUILD_DIR="/tmp/open-vm-tools-build"
echo "Cloning open-vm-tools repository..."
rm -rf "$BUILD_DIR"
git clone https://github.com/vmware/open-vm-tools.git "$BUILD_DIR"

cd "$BUILD_DIR/open-vm-tools"
echo "Building open-vm-tools (this may take several minutes)..."
if ! autoreconf -i; then
  echo ""
  echo "WARNING: Failed to run autoreconf - skipping VMware Tools installation"
  echo ""
  cd /
  rm -rf "$BUILD_DIR"
  return 0
fi

if ! ./configure; then
  echo ""
  echo "WARNING: Failed to configure build - skipping VMware Tools installation"
  echo ""
  cd /
  rm -rf "$BUILD_DIR"
  return 0
fi

if ! make -j$(nproc); then
  echo ""
  echo "WARNING: Failed to compile - skipping VMware Tools installation"
  echo ""
  cd /
  rm -rf "$BUILD_DIR"
  return 0
fi

if ! sudo make install; then
  echo ""
  echo "WARNING: Failed to install - skipping VMware Tools installation"
  echo ""
  cd /
  rm -rf "$BUILD_DIR"
  return 0
fi

# Verify installation
if [ ! -f /usr/local/bin/vmtoolsd ]; then
  echo ""
  echo "WARNING: vmtoolsd was not installed to /usr/local/bin/vmtoolsd - skipping VMware Tools"
  echo ""
  cd /
  rm -rf "$BUILD_DIR"
  return 0
fi

# Create systemd service
echo "Creating systemd service..."
sudo tee /etc/systemd/system/vmtoolsd.service <<'EOF' >/dev/null
[Unit]
Description=Open VM Tools
Documentation=https://github.com/vmware/open-vm-tools
ConditionVirtualization=vmware
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/vmtoolsd
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Enable and start service
echo "Enabling and starting vmtoolsd service..."
sudo systemctl daemon-reexec
sudo systemctl enable vmtoolsd.service
sudo systemctl start vmtoolsd.service

# Create user service for clipboard support
echo "Creating vmware-user service for clipboard support..."
sudo tee /etc/systemd/user/vmware-user.service <<'EOF' >/dev/null
[Unit]
Description=VMware User Agent (clipboard and DnD support)
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=forking
ExecStart=/bin/sh -c 'sleep 3 && exec /usr/local/bin/vmware-user'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
EOF

# Enable for all users
sudo systemctl --global enable vmware-user.service

# Create HGFS shared folders mount
echo "Configuring VMware shared folders auto-mount..."
sudo mkdir -p /mnt/hgfs

sudo tee /etc/systemd/system/mnt-hgfs.mount <<'EOF' >/dev/null
[Unit]
Description=VMware HGFS Shared Folders
After=vmtoolsd.service
Requires=vmtoolsd.service
ConditionVirtualization=vmware

[Mount]
What=.host:/
Where=/mnt/hgfs
Type=fuse.vmhgfs-fuse
Options=allow_other

[Install]
WantedBy=multi-user.target
EOF

# Enable and start HGFS mount
echo "Enabling VMware shared folders..."
sudo systemctl daemon-reload
sudo systemctl enable mnt-hgfs.mount
sudo systemctl start mnt-hgfs.mount

# Create script to sync shared folder symlinks to Desktop
sudo tee /usr/local/bin/sync-vmware-desktop-links <<'EOF' >/dev/null
#!/bin/bash
# Sync VMware shared folders to Desktop symlinks

for user_home in /home/*; do
  [ -d "$user_home" ] || continue
  username=$(basename "$user_home")
  desktop_dir="$user_home/Desktop"

  [ -d "$desktop_dir" ] || continue

  # Create symlinks for each shared folder
  for folder in /mnt/hgfs/*; do
    [ -d "$folder" ] || continue
    folder_name=$(basename "$folder")
    link_path="$desktop_dir/$folder_name"

    # Create or update symlink
    if [ ! -L "$link_path" ] || [ "$(readlink "$link_path")" != "$folder" ]; then
      sudo -u "$username" ln -sf "$folder" "$link_path"
    fi
  done

  # Remove broken symlinks that point to /mnt/hgfs
  for link in "$desktop_dir"/*; do
    [ -L "$link" ] || continue
    target=$(readlink "$link")
    # If it's a symlink to /mnt/hgfs and the target doesn't exist, remove it
    if [[ "$target" == /mnt/hgfs/* ]] && [ ! -e "$target" ]; then
      sudo -u "$username" rm "$link"
    fi
  done
done
EOF

sudo chmod +x /usr/local/bin/sync-vmware-desktop-links

# Create watcher service that monitors vmware-hgfsclient output
sudo tee /etc/systemd/system/vmware-desktop-watcher.service <<'EOF' >/dev/null
[Unit]
Description=VMware Shared Folders Watcher
After=mnt-hgfs.mount vmtoolsd.service
Requires=mnt-hgfs.mount vmtoolsd.service
ConditionVirtualization=vmware

[Service]
Type=simple
ExecStart=/bin/bash -c 'LAST=""; while true; do CURRENT=$(vmware-hgfsclient 2>/dev/null | sort); if [ "$CURRENT" != "$LAST" ]; then systemctl start vmware-desktop-links.service; LAST="$CURRENT"; fi; sleep 2; done'
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Create systemd service to run sync script
sudo tee /etc/systemd/system/vmware-desktop-links.service <<'EOF' >/dev/null
[Unit]
Description=Sync VMware shared folders to Desktop
After=mnt-hgfs.mount

[Service]
Type=oneshot
ExecStart=/usr/local/bin/sync-vmware-desktop-links
EOF

# Enable watcher and run initial sync
echo "Enabling VMware Desktop integration..."
sudo systemctl daemon-reload
sudo systemctl enable vmware-desktop-watcher.service
sudo systemctl start vmware-desktop-watcher.service
sudo systemctl start vmware-desktop-links.service

# Cleanup
cd /
rm -rf "$BUILD_DIR"

echo "VMware Tools installation complete!"
echo "Shared folders will be available at /mnt/hgfs/"
echo "Desktop shortcuts will be automatically created for all shared folders"
