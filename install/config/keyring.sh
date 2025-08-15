#!/bin/bash

# Install dependencies
yay -S --noconfirm --needed pass pass-secret-service-bin

# STEP 1: Generate GPG key non-interactively and capture output
if [ -z "$OMARCHY_USER_NAME" ] || [ -z "$OMARCHY_USER_EMAIL" ]; then
    GPG_OUTPUT=$(cat <<EOF | gpg --batch --generate-key 2>&1
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: Omarchy
Name-Email: omarchy@keyring.local
Expire-Date: 0
EOF
)
else
    GPG_OUTPUT=$(cat <<EOF | gpg --batch --generate-key 2>&1
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: $OMARCHY_USER_NAME
Name-Email: $OMARCHY_USER_EMAIL
Expire-Date: 0
EOF
)
fi

# STEP 2: Get the GPG key ID from the output
GPG_ID=$(echo "$GPG_OUTPUT" | grep 'openpgp-revocs.d' | grep -o '[A-F0-9]\{16\}\.rev' | cut -d'.' -f1)
if [ -z "$GPG_ID" ]; then
    echo "Error: Failed to find GPG key ID in output: $GPG_OUTPUT"
    exit 1
fi

# STEP 3: Initialize the password store with the GPG key ID
pass init "$GPG_ID"
