# ----------------------
# Helper functions
# ----------------------
check_process() {
  pgrep -u "$USER" "$1" >/dev/null 2>&1
  return $?
}

check_package() {
  yay -Qs "$1" >/dev/null 2>&1
  return $?
}

check_directory() {
  [ -d "$1" ] && [ "$(ls -A "$1")" ]
  return $?
}

# ----------------------
# Initialize flags
# ----------------------
gnome_keyring_in_use=0

# ----------------------
# Migration logic
# ----------------------
# STEP 1: Check for GNOME Keyring
echo -n "Checking for GNOME Keyring... "
if check_process "gnome-keyring" || check_package "gnome-keyring" || check_directory "$HOME/.local/share/keyrings"; then
  echo "GNOME Keyring is in use."
  gnome_keyring_in_use=1
else
  echo "GNOME Keyring not detected."
fi

# STEP 2: Generate GPG key non-interactively and capture output
GPG_OUTPUT=$(
  cat <<EOF | gpg --batch --generate-key 2>&1
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omarchy
Name-Email: omarchy@keyring.local
Expire-Date: 0
EOF
)

# STEP 3: Make sure we can get the GPG key ID from the output before we modify existing keyring solution
GPG_ID=$(echo "$GPG_OUTPUT" | grep 'openpgp-revocs.d' | grep -o '[A-F0-9]\{16\}\.rev' | cut -d'.' -f1)
if [ -z "$GPG_ID" ]; then
  echo "Error: Failed to find GPG key ID in output: $GPG_OUTPUT"
  exit 1
fi

# STEP 4: Summary and decision for pass
echo -e "\nSummary:"
if [ $gnome_keyring_in_use -eq 1 ]; then
  echo "WARNING - Gnome Keyring detected."

  # Get user confirmation to proceed
  choice=$(gum choose --header "Omarchy is migrating the OS keystore to pass. You will need to manually \
migrate secrets from existing keyrings.
Do you want to replace gnome-keyring with pass?" "No" "Yes")
  if [ "$choice" = "Yes" ]; then
    # Remove gnome-keyring
    echo "Removing GNOME Keyring..."
    pkill -u $USER gnome-keyring
    yay -Rns --noconfirm gnome-keyring
    mv ~/.local/share/keyrings ~/.local/share/gnome-keyrings-archiv

    # Install pass
    yay -S --noconfirm --needed pass pass-secret-service-bin

    # Initialize pass
    if [ ! -d "$HOME/.password-store" ]; then
      echo "Initializing pass..."
      pass init $GPG_ID
    else
      echo "pass is already initialized."
    fi
    echo "pass has been set up. You will need to manually migrate secrets from existing keyrings."
  else
    echo "Declined to set up pass. Exiting."
    exit 0
  fi
else
  echo "No existing secrets backends detected. Safe to install and activate pass."
  # Install pass if not already installed
  yay -S --noconfirm --needed pass pass-secret-service-bin

  # Initialize pass
  if [ ! -d "$HOME/.password-store" ]; then
    echo "Initializing pass..."
    pass init $GPG_ID
  else
    echo "pass is already initialized."
  fi
fi
