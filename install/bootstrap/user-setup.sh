#!/bin/bash

# Set defaults for repo/ref if not provided
OMARCHY_REPO="${OMARCHY_REPO:-basecamp/omarchy}"
OMARCHY_REF="${OMARCHY_REF:-master}"

# Detect ARM architecture if not already set
if [ -z "$OMARCHY_ARM" ]; then
  arch=$(uname -m)
  if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    export OMARCHY_ARM=true
  fi
fi

# Detect if we're on Asahi Linux / Apple Silicon
# Check kernel name OR device tree for Apple hardware (newer kernels may not have "asahi" in name)
is_asahi=false
if uname -r | grep -qi "asahi" || grep -q "apple" /sys/firmware/devicetree/base/compatible 2>/dev/null; then
  is_asahi=true
  export GUM_CHOOSE_CURSOR="> "
  export GUM_CHOOSE_CURSOR_PREFIX="* "
  export GUM_CHOOSE_SELECTED_PREFIX="[x] "
  export GUM_CHOOSE_UNSELECTED_PREFIX="[ ] "
fi

existing_users=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)

if [[ $EUID -eq 0 ]]; then
  # Update mirrorlist to avoid broken geo mirror before syncing database
  if [[ -n "$OMARCHY_ARM" ]]; then
    echo
    echo "Configuring ARM mirrors (downloading from GitHub)..."
    if curl -fsSL "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/default/pacman/mirrorlist.arm" -o /tmp/omarchy-mirrorlist.arm 2>/dev/null; then
      cp -f /tmp/omarchy-mirrorlist.arm /etc/pacman.d/mirrorlist
      rm -f /tmp/omarchy-mirrorlist.arm
      echo "Updated mirrorlist to use Florida mirror (avoiding broken geo mirror)"
    else
      echo "Warning: Could not download mirrorlist, using system default"
    fi
  fi

  # Sync package database first to ensure we have current package versions
  echo
  echo "Syncing package database..."
  sync_attempts=0
  max_sync_attempts=3
  sync_success=false

  while [ $sync_attempts -lt $max_sync_attempts ]; do
    if pacman -Sy --noconfirm 2>&1; then
      sync_success=true
      break
    fi
    sync_attempts=$((sync_attempts + 1))
    if [ $sync_attempts -lt $max_sync_attempts ]; then
      echo "Database sync failed (attempt $sync_attempts/$max_sync_attempts), retrying in 3 seconds..."
      sleep 3
    fi
  done

  if [ "$sync_success" = false ]; then
    echo "ERROR: Failed to sync package database after $max_sync_attempts attempts"
    echo "This may be due to slow/unreachable mirrors or network issues."
    echo "Please check your network connection and try again."
    exit 1
  fi
  echo

  # Install gum for user interaction (needed in bootstrap mode when helpers aren't sourced)
  if ! command -v gum &>/dev/null; then
    echo "Installing gum for interactive setup..."
    gum_output=$(mktemp)
    if ! pacman -S --needed --noconfirm gum >"$gum_output" 2>&1; then
      echo "Error: Failed to install the 'gum' package"
      echo "--- pacman output ---"
      cat "$gum_output"
      echo "---------------------"
      rm -f "$gum_output"
      exit 1
    fi
    rm -f "$gum_output"
    echo "Gum installed successfully!"
    echo
  fi

  echo "------------------------------------------------------"
  echo "Use arrow keys to navigate, and press Enter to confirm"
  echo "------------------------------------------------------"

  if [ -n "$existing_users" ]; then
    # Convert existing users to an array for gum
    readarray -t user_array <<< "$existing_users"

    # Loop until we get valid input
    while true; do
      # Show user list before prompting
      echo
      echo "Found existing users:"
      echo "$existing_users" | tr ' ' '\n' | sed 's/^/  - /'

      # Calculate lines to clear: 1 blank line + 1 header + number of users
      lines_to_clear=$((2 + ${#user_array[@]}))

      echo
      # Force TTY allocation for gum when running from piped script
      if gum confirm "Use an existing user account?" < /dev/tty; then
        # Clear the user list by moving cursor up and clearing lines
        printf "\033[${lines_to_clear}A\033[J"
        username=$(gum choose --header "Select user:" "${user_array[@]}" < /dev/tty)
        exit_code=$?

        # Check for Ctrl+C (exit code 130) and exit cleanly
        if [ $exit_code -eq 130 ]; then
          echo
          echo "Installation cancelled."
          echo
          exit 130
        fi

        # Check if user cancelled with ESC or nothing was selected
        if [ $exit_code -ne 0 ] || [ -z "$username" ]; then
          continue
        fi
      else
        printf "\033[${lines_to_clear}A\033[J"
        username=$(gum input --placeholder "Enter a new username for Omarchy" < /dev/tty)
        exit_code=$?

        if [ $exit_code -eq 130 ]; then
          echo
          echo "Installation cancelled."
          echo
          exit 130
        fi

        # Check if username is empty or only spaces
        if [ -z "$username" ] || [ -z "$(echo "$username" | tr -d ' ')" ]; then
          echo "No username entered. Please try again."
          continue
        fi

        # Validate username format and length
        if [ ${#username} -gt 32 ]; then
          echo "Username too long (max 32 characters). Please try again."
          continue
        fi

        if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
          echo "Invalid username. Must start with a letter or underscore, and contain only lowercase letters, digits, underscores, or hyphens."
          continue
        fi
      fi
      break
    done
  else
    # Loop until we get valid input for new user
    while true; do
      echo
      username=$(gum input --placeholder "Enter a username for Omarchy" < /dev/tty)
      exit_code=$?

      if [ $exit_code -eq 130 ]; then
        echo
        echo "Installation cancelled."
        echo
        exit 130
      fi

      # Check if username is empty or only spaces
      if [ -z "$username" ] || [ -z "$(echo "$username" | tr -d ' ')" ]; then
        echo "No username entered. Please try again."
        continue
      fi

      # Validate username format and length
      if [ ${#username} -gt 32 ]; then
        echo "Username too long (max 32 characters). Please try again."
        continue
      fi

      if ! [[ "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Invalid username. Must start with a letter or underscore, and contain only lowercase letters, digits, underscores, or hyphens."
        continue
      fi

      break
    done
  fi

  # Create user if doesn't exist
  if ! id "$username" &>/dev/null; then
    gum style --foreground 99 "Creating user and setting password..."
    if [ "$is_asahi" = true ]; then
      gum style --foreground 244 "Note: Password will not be masked (Asahi's initial TTY can't display masking characters properly) but your user will be created securely."
    fi
    useradd -m "$username"

    while true; do
      echo
      if [ "$is_asahi" = true ]; then
        password=$(gum input --placeholder "Enter password for $username" < /dev/tty)
      else
        password=$(gum input --password --placeholder "Enter password for $username" < /dev/tty)
      fi
      exit_code=$?

      if [ $exit_code -eq 130 ]; then
        echo
        echo "Installation cancelled."
        echo
        exit 130
      fi

      if [ -z "$password" ]; then
        echo "No password supplied. Please try again."
        continue
      fi

      if [[ "$password" =~ [[:space:]] ]]; then
        echo "Password cannot contain spaces. Please try again."
        continue
      fi

      if [ "$is_asahi" = true ]; then
        password_confirm=$(gum input --placeholder "Confirm password" < /dev/tty)
      else
        password_confirm=$(gum input --password --placeholder "Confirm password" < /dev/tty)
      fi
      exit_code=$?

      if [ $exit_code -eq 130 ]; then
        echo
        echo "Installation cancelled."
        echo
        exit 130
      fi

      if [ "$password" = "$password_confirm" ]; then
        echo "$username:$password" | chpasswd
        break
      else
        echo "Passwords don't match. Please try again."
      fi
    done

    usermod -aG wheel "$username"
    echo "Added $username to wheel group"
  else
    echo "Using existing user $username"
    # Ensure user is in wheel group even if they already exist
    usermod -aG wheel "$username"
  fi

  # Collect user details for git configuration
  while true; do # Loop until we get a valid full name
    echo
    user_fullname=$(gum input --placeholder "Enter your full name (for git config)" < /dev/tty)
    exit_code=$?

    if [ $exit_code -eq 130 ]; then
      echo
      echo "Installation cancelled."
      echo
      exit 130
    fi

    # Check if full name is empty or only spaces
    if [ -z "$user_fullname" ] || [ -z "$(echo "$user_fullname" | tr -d ' ')" ]; then
      echo "Full name is required. Please try again."
      continue
    fi

    # Validate full name length
    if [ ${#user_fullname} -gt 50 ]; then
      echo "Full name too long (max 50 characters). Please try again."
      continue
    fi
    break
  done

  echo "Saved full name: $user_fullname"

  while true; do # Loop until we get a valid email
    echo
    user_email=$(gum input --placeholder "Enter your email address (for git config)" < /dev/tty)
    exit_code=$?

    if [ $exit_code -eq 130 ]; then
      echo
      echo "Installation cancelled."
      echo
      exit 130
    fi

    # Check if email is empty or only spaces
    if [ -z "$user_email" ] || [ -z "$(echo "$user_email" | tr -d ' ')" ]; then
      echo "Email address is required. Please try again."
      continue
    fi

    # Check for spaces in email
    if [[ "$user_email" =~ [[:space:]] ]]; then
      echo "Email address cannot contain spaces. Please try again."
      continue
    fi

    # Basic email validation: must contain @ and have text before and after it
    if [[ ! "$user_email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
      echo "Invalid email format. Please enter a valid email address (e.g., user@example.com)."
      continue
    fi
    break
  done

  echo "Saved email address: $user_email"
  echo
  echo "Finalizing user permissions..."

  if ! command -v sudo &>/dev/null; then
    echo "  - Installing sudo..."
    sudo_output=$(mktemp)
    if ! pacman -S --needed --noconfirm sudo >"$sudo_output" 2>&1; then
      echo "    Error: Failed to install the 'sudo' package"
      echo "--- pacman output ---"
      cat "$sudo_output"
      echo "---------------------"
      rm -f "$sudo_output"
      exit 1
    fi
    rm -f "$sudo_output"
    echo "  - Sudo installed successfully"
  fi

  # Handle both formats: %wheel ALL=(ALL:ALL) ALL and %wheel ALL=(ALL) ALL
  if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    echo "  - Enabled sudo for wheel group"
  elif grep -q "^# %wheel ALL=(ALL) ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
    echo "  - Enabled sudo for wheel group"
  elif ! grep -qE "^%wheel ALL=\(ALL(:ALL)?\) ALL" /etc/sudoers; then
    echo "%wheel ALL=(ALL:ALL) ALL" >>/etc/sudoers
    echo "  - Added wheel group to sudoers"
  fi

  # Remove user-specific sudo rules from /etc/sudoers that override sudoers.d
  # Some ARM images (Arch ARM, EndeavourOS) add user rules AFTER #includedir,
  # which override anything in sudoers.d (last match wins in sudoers)
  if grep -qE "^${username}[[:space:]]+ALL=" /etc/sudoers; then
    sed -i "/^${username}[[:space:]]\+ALL=/d" /etc/sudoers
    echo "  - Removed '$username' rule from /etc/sudoers (was overriding sudoers.d)"
  fi
  if grep -qE "^alarm[[:space:]]+ALL=" /etc/sudoers; then
    sed -i "/^alarm[[:space:]]\+ALL=/d" /etc/sudoers
    echo "  - Removed 'alarm' rule from /etc/sudoers (Arch ARM default, overrides sudoers.d)"
  fi

  # Temporarily allow passwordless sudo for the installation
  # Ensure sudoers.d directory exists (should on standard Arch, but be safe)
  mkdir -p /etc/sudoers.d

  # Create the temp sudoers file
  echo "$username ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/omarchy-temp
  chmod 440 /etc/sudoers.d/omarchy-temp

  # Verify the file was created and has correct syntax
  if [ ! -f /etc/sudoers.d/omarchy-temp ]; then
    echo "  - ERROR: Failed to create temporary sudoers file"
    exit 1
  fi

  # Validate sudoers syntax (visudo -c checks all sudoers files)
  if ! visudo -c -q 2>/dev/null; then
    echo "  - ERROR: Invalid sudoers syntax, removing temp file"
    rm -f /etc/sudoers.d/omarchy-temp
    exit 1
  fi

  # Clear any cached sudo credentials to ensure new rules take effect
  sudo -k 2>/dev/null || true

  echo "  - Enabled temporary passwordless sudo for installation"

  # Re-run the boot script as the new user to continue installation
  # Pass repo/ref and user details to continue installation as the new user
  # Use printf %q to safely escape variables containing special characters
  escaped_fullname=$(printf '%q' "${user_fullname}")
  escaped_email=$(printf '%q' "${user_email}")

  # Build install command with sudo cleanup at the end
  install_cmd="export \
    HOME=/home/$username \
    USER=$username \
    OMARCHY_REPO='${OMARCHY_REPO}' \
    OMARCHY_REF='${OMARCHY_REF}' \
    OMARCHY_USER_NAME=${escaped_fullname} \
    OMARCHY_USER_EMAIL=${escaped_email} \
    OMARCHY_SIMULATE_AUR_DOWN='${OMARCHY_SIMULATE_AUR_DOWN:-}' \
    OMARCHY_SIMULATE_MIRROR_DOWN='${OMARCHY_SIMULATE_MIRROR_DOWN:-}' \
    SKIP_ALL='${SKIP_ALL:-}' \
    SKIP_YARU='${SKIP_YARU:-}' \
    SKIP_OBS='${SKIP_OBS:-}' \
    SKIP_PINTA='${SKIP_PINTA:-}' \
    SKIP_GHOSTTY='${SKIP_GHOSTTY:-}' \
    SKIP_SIGNAL_DESKTOP_BETA='${SKIP_SIGNAL_DESKTOP_BETA:-}'; \
    cd /home/$username; \
    curl -fsSL https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/boot.sh | bash; \
    install_result=\$?; \
    sudo rm -f /etc/sudoers.d/omarchy-temp 2>/dev/null && echo && echo 'Removed temporary passwordless sudo config for $username' && echo; \
    exit \$install_result"

  # Ensure runuser is available for better terminal handling
  if ! command -v runuser &>/dev/null; then
    echo "  - Installing runuser for better terminal handling..."
    runuser_output=$(mktemp)
    if ! pacman -S --needed --noconfirm util-linux >"$runuser_output" 2>&1; then
      echo "    Error: Failed to install util-linux package"
      echo "--- pacman output ---"
      cat "$runuser_output"
      echo "---------------------"
      rm -f "$runuser_output"
      exit 1
    fi
    rm -f "$runuser_output"
    echo "  - Runuser installed successfully"
  fi

  echo

  # Confirm before proceeding with installation
  if ! GUM_CONFIRM_PADDING="0 0 2 0" gum confirm "Ready to install Omarchy as $username?" < /dev/tty; then
    echo
    echo "Installation cancelled."
    echo
    exit 130
  fi

  runuser -u $username -- bash -c "$install_cmd"

  # Exit after su completes to prevent further execution as root
  exit 0
fi

echo "No non-root users detected on this system. Initial setup must be run as root to create a non-root user."
echo "Please run this script as root."
exit 1
