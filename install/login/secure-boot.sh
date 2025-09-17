#!/bin/bash

if command -v sbctl &> /dev/null; then
    echo "Installing Omarchy secure boot automation..."
    
    # Install the script
    sudo cp $OMARCHY_PATH/files/bin/omarchy-secure-boot-update.sh /usr/local/bin/
    sudo chmod +x /usr/local/bin/omarchy-secure-boot-update.sh
    
    # Install the pacman hook
    sudo cp $OMARCHY_PATH/files/hooks/99-omarchy-secure-boot.hook /etc/pacman.d/hooks/
    
    echo "Secure boot automation installed successfully"
else
    echo "sbctl not found, skipping secure boot automation"
fi
