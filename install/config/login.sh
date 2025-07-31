#!/bin/bash

# Hyprland launched via UWSM and login directly as user, rely on disk encryption + hyprlock for security
if ! command -v uwsm &>/dev/null || ! command -v plymouth &>/dev/null; then
  yay -S --noconfirm --needed uwsm plymouth
fi

# ==============================================================================
# PLYMOUTH SETUP
# ==============================================================================

if ! grep -Eq '^HOOKS=.*plymouth' /etc/mkinitcpio.conf; then
  # Backup original mkinitcpio.conf just in case
  backup_timestamp=$(date +"%Y%m%d%H%M%S")
  sudo cp /etc/mkinitcpio.conf "/etc/mkinitcpio.conf.bak.${backup_timestamp}"

  # Add plymouth to HOOKS array after 'base udev' or 'base systemd'
  if grep "^HOOKS=" /etc/mkinitcpio.conf | grep -q "base systemd"; then
    sudo sed -i '/^HOOKS=/s/base systemd/base systemd plymouth/' /etc/mkinitcpio.conf
  elif grep "^HOOKS=" /etc/mkinitcpio.conf | grep -q "base udev"; then
    sudo sed -i '/^HOOKS=/s/base udev/base udev plymouth/' /etc/mkinitcpio.conf
  else
    echo "Couldn't add the Plymouth hook"
  fi

  # Regenerate initramfs
  sudo mkinitcpio -P
fi

# Add kernel parameters for Plymouth
if [ -d "/boot/loader/entries" ]; then # systemd-boot
  echo "Detected systemd-boot"

  for entry in /boot/loader/entries/*.conf; do
    if [ -f "$entry" ]; then
      # Skip fallback entries
      if [[ "$(basename "$entry")" == *"fallback"* ]]; then
        echo "Skipped: $(basename "$entry") (fallback entry)"
        continue
      fi

      # Skip if splash it already present for some reason
      if ! grep -q "splash" "$entry"; then
        sudo sed -i '/^options/ s/$/ splash quiet/' "$entry"
      else
        echo "Skipped: $(basename "$entry") (splash already present)"
      fi
    fi
  done
elif [ -f "/etc/default/grub" ]; then # Grub
  echo "Detected grub"

  # Backup GRUB config before modifying
  backup_timestamp=$(date +"%Y%m%d%H%M%S")
  sudo cp /etc/default/grub "/etc/default/grub.bak.${backup_timestamp}"

  # Check if splash is already in GRUB_CMDLINE_LINUX_DEFAULT
  if ! grep -q "GRUB_CMDLINE_LINUX_DEFAULT.*splash" /etc/default/grub; then
    # Get current GRUB_CMDLINE_LINUX_DEFAULT value
    current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub | cut -d'"' -f2)

    # Add splash and quiet if not present
    new_cmdline="$current_cmdline"
    if [[ ! "$current_cmdline" =~ splash ]]; then
      new_cmdline="$new_cmdline splash"
    fi
    if [[ ! "$current_cmdline" =~ quiet ]]; then
      new_cmdline="$new_cmdline quiet"
    fi

    # Trim any leading/trailing spaces
    new_cmdline=$(echo "$new_cmdline" | xargs)

    sudo sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\".*\"/GRUB_CMDLINE_LINUX_DEFAULT=\"$new_cmdline\"/" /etc/default/grub

    # Regenerate grub config
    sudo grub-mkconfig -o /boot/grub/grub.cfg
  else
    echo "GRUB already configured with splash kernel parameters"
  fi
elif [ -d "/etc/cmdline.d" ]; then # UKI
  echo "Detected a UKI setup"
  # Relying on mkinitcpio to assemble a UKI
  # https://wiki.archlinux.org/title/Unified_kernel_image
  if ! grep -q splash /etc/cmdline.d/*.conf; then
    # Need splash, create the omarchy file
    echo "splash" | sudo tee -a /etc/cmdline.d/omarchy.conf
  fi
  if ! grep -q quiet /etc/cmdline.d/*.conf; then
    # Need quiet, create or append the omarchy file
    echo "quiet" | sudo tee -a /etc/cmdline.d/omarchy.conf
  fi
elif [ -f "/etc/kernel/cmdline" ]; then # UKI Alternate
  # Alternate UKI kernel cmdline location
  echo "Detected a UKI setup"

  # Backup kernel cmdline config before modifying
  backup_timestamp=$(date +"%Y%m%d%H%M%S")
  sudo cp /etc/kernel/cmdline "/etc/kernel/cmdline.bak.${backup_timestamp}"

  current_cmdline=$(cat /etc/kernel/cmdline)

  # Add splash and quiet if not present
  new_cmdline="$current_cmdline"
  if [[ ! "$current_cmdline" =~ splash ]]; then
    new_cmdline="$new_cmdline splash"
  fi
  if [[ ! "$current_cmdline" =~ quiet ]]; then
    new_cmdline="$new_cmdline quiet"
  fi

  # Trim any leading/trailing spaces
  new_cmdline=$(echo "$new_cmdline" | xargs)

  # Write new file
  echo $new_cmdline | sudo tee /etc/kernel/cmdline
else
  echo ""
  echo " None of systemd-boot, GRUB, or UKI detected. Please manually add these kernel parameters:"
  echo "  - splash (to see the graphical splash screen)"
  echo "  - quiet (for silent boot)"
  echo ""
fi

if [ "$(plymouth-set-default-theme)" != "omarchy" ]; then
  sudo cp -r "$HOME/.local/share/omarchy/default/plymouth" /usr/share/plymouth/themes/omarchy/
  sudo plymouth-set-default-theme -R omarchy
fi

# ==============================================================================
# SEAMLESS LOGIN
# ==============================================================================

if [ ! -x /usr/local/bin/seamless-login ]; then
  # Compile the seamless login helper -- needed to prevent seeing terminal between loader and desktop
  cat <<'CCODE' >/tmp/seamless-login.c
/*
* Seamless Login - Minimal SDDM-style Plymouth transition
* Replicates SDDM's VT management for seamless auto-login
*/
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <linux/kd.h>
#include <linux/vt.h>
#include <sys/wait.h>
#include <string.h>

int main(int argc, char *argv[]) {
    int vt_fd;
    int vt_num = 1; // TTY1
    char vt_path[32];
    
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <session_command>\n", argv[0]);
        return 1;
    }
    
    // Open the VT (simple approach like SDDM)
    snprintf(vt_path, sizeof(vt_path), "/dev/tty%d", vt_num);
    vt_fd = open(vt_path, O_RDWR);
    if (vt_fd < 0) {
        perror("Failed to open VT");
        return 1;
    }
    
    // Activate the VT
    if (ioctl(vt_fd, VT_ACTIVATE, vt_num) < 0) {
        perror("VT_ACTIVATE failed");
        close(vt_fd);
        return 1;
    }
    
    // Wait for VT to be active
    if (ioctl(vt_fd, VT_WAITACTIVE, vt_num) < 0) {
        perror("VT_WAITACTIVE failed");
        close(vt_fd);
        return 1;
    }
    
    // Critical: Set graphics mode to prevent console text
    if (ioctl(vt_fd, KDSETMODE, KD_GRAPHICS) < 0) {
        perror("KDSETMODE KD_GRAPHICS failed");
        close(vt_fd);
        return 1;
    }
    
    // Clear VT and close (like SDDM does)
    const char *clear_seq = "\33[H\33[2J";
    if (write(vt_fd, clear_seq, strlen(clear_seq)) < 0) {
        perror("Failed to clear VT");
    }
    
    close(vt_fd);
    
    // Set working directory to user's home
    const char *home = getenv("HOME");
    if (home) chdir(home);
    
    // Now execute the session command
    execvp(argv[1], &argv[1]);
    perror("Failed to exec session");
    return 1;
}
CCODE

  gcc -o /tmp/seamless-login /tmp/seamless-login.c
  sudo mv /tmp/seamless-login /usr/local/bin/seamless-login
  sudo chmod +x /usr/local/bin/seamless-login
  rm /tmp/seamless-login.c
fi

if [ ! -f /etc/systemd/system/omarchy-seamless-login.service ]; then
  cat <<EOF | sudo tee /etc/systemd/system/omarchy-seamless-login.service
[Unit]
Description=Omarchy Seamless Auto-Login
Documentation=https://github.com/basecamp/omarchy
Conflicts=getty@tty1.service
After=systemd-user-sessions.service getty@tty1.service plymouth-quit.service systemd-logind.service
PartOf=graphical.target

[Service]
Type=simple
ExecStart=/usr/local/bin/seamless-login uwsm start -- hyprland.desktop
Restart=on-failure
RestartSec=5
User=$USER
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
StandardInput=tty
StandardOutput=journal
StandardError=journal+console
PAMName=login

[Install]
WantedBy=graphical.target
EOF
fi

if [ ! -f /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf ]; then
  # Make plymouth remain until graphical.target
  sudo mkdir -p /etc/systemd/system/plymouth-quit.service.d
  sudo tee /etc/systemd/system/plymouth-quit.service.d/wait-for-graphical.conf <<'EOF'
[Unit]
After=multi-user.target
EOF
fi

# Mask plymouth-quit-wait.service only if not already masked
if ! systemctl is-enabled plymouth-quit-wait.service | grep -q masked; then
  sudo systemctl mask plymouth-quit-wait.service
  sudo systemctl daemon-reload
fi

# Enable omarchy-seamless-login.service only if not already enabled
if ! systemctl is-enabled omarchy-seamless-login.service | grep -q enabled; then
  sudo systemctl enable omarchy-seamless-login.service
fi

# Disable getty@tty1.service only if not already disabled
if ! systemctl is-enabled getty@tty1.service | grep -q disabled; then
  sudo systemctl disable getty@tty1.service
fi
