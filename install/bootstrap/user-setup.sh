#!/bin/bash

# Detect if we need ASCII rendering (ARM, Asahi, or VM)
# This matches the detection logic in install.sh
is_asahi=false

# Detect ARM
arch=$(uname -m)
if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
  export OMARCHY_ARM=true
fi

# Detect Asahi specifically
if uname -r | grep -qi "asahi"; then
  is_asahi=true
  export ASAHI_ALARM=true
fi

# Detect virtualization
if command -v systemd-detect-virt &>/dev/null; then
  virt_type=$(systemd-detect-virt || echo "none")
  if [[ "$virt_type" != "none" ]]; then
    export OMARCHY_VIRTUALIZATION=true
  fi
fi

# Suppress gum help and use simple ASCII on ARM/Asahi/VMs
if [[ -n "$OMARCHY_ARM" ]] || [[ "$is_asahi" == "true" ]] || [[ -n "$OMARCHY_VIRTUALIZATION" ]]; then
  export GUM_CHOOSE_CURSOR="> "
  export GUM_CHOOSE_CURSOR_PREFIX="* "
  export GUM_CHOOSE_SELECTED_PREFIX="[x] "
  export GUM_CHOOSE_UNSELECTED_PREFIX="[ ] "
  export GUM_CONFIRM_SHOW_HELP=false
  export GUM_CHOOSE_SHOW_HELP=false
fi

existing_users=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)

if [[ $EUID -eq 0 ]]; then
  # Install gum for user interaction (needed in bootstrap mode when helpers aren't sourced)
  if ! command -v gum &>/dev/null; then
    echo
    echo "Installing gum for interactive setup..."
    pacman -S --needed --noconfirm gum >/dev/null 2>&1 || {
      echo "Error: Failed to install the 'gum' package"
      exit 1
    }
    echo "Gum installed successfully!"
    echo
    echo "------------------------------------------------------"
  fi

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
      if gum confirm --show-help=false "Use an existing user account?" < /dev/tty; then
        # Clear the user list by moving cursor up and clearing lines
        printf "\033[${lines_to_clear}A\033[J"
        username=$(gum choose --show-help=false --header "Select user:" "${user_array[@]}" < /dev/tty)
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
    pacman -S --needed --noconfirm sudo >/dev/null 2>&1 || {
      echo "    Error: Failed to install the 'sudo' package"
      exit 1
    }
    echo "  - Sudo installed successfully"
  fi

  if grep -q "^# %wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    echo "  - Enabled sudo for wheel group"
  elif ! grep -q "^%wheel ALL=(ALL:ALL) ALL" /etc/sudoers; then
    echo "%wheel ALL=(ALL:ALL) ALL" >>/etc/sudoers
    echo "  - Added wheel group to sudoers"
  fi

  # Temporarily allow passwordless sudo for the installation
  echo "$username ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/omarchy-temp
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
    cd /home/$username; \
    curl -fsSL https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF}/boot.sh | bash; \
    install_result=\$?; \
    sudo rm -f /etc/sudoers.d/omarchy-temp 2>/dev/null && echo && echo 'Removed temporary passwordless sudo config for $username' && echo; \
    exit \$install_result"

  # Ensure runuser is available for better terminal handling
  if ! command -v runuser &>/dev/null; then
    echo "  - Installing runuser for better terminal handling..."
    pacman -S --needed --noconfirm util-linux >/dev/null 2>&1 || {
      echo "    Error: Failed to install util-linux package"
      exit 1
    }
    echo "  - Runuser installed successfully"
  fi

  echo

  # Confirm before proceeding with installation
  if ! gum confirm --show-help=false "Ready to install Omarchy as $username?" < /dev/tty; then
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
