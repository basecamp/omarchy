#!/bin/bash

if command -v sbctl &> /dev/null; then
    echo ""
    read -p "Do you want to set up Secure Boot with custom keys? (y/N): " setup_sb
    
    if [[ $setup_sb =~ ^[Yy]$ ]]; then
        if [[ ! -f /usr/share/secureboot/keys/db/db.key ]]; then
            echo "Creating secure boot keys..."
            sudo sbctl create-keys
            
            echo ""
            echo "🔐 Secure Boot Setup Instructions:"
            echo "================================================="
            echo "1. Reboot and enter BIOS/UEFI setup"
            echo "2. Clear existing secure boot keys (enter Setup Mode)"
            echo "3. Save and reboot back to Omarchy"
            echo "4. Run: sudo sbctl enroll-keys -m -f"
            echo "5. Reboot and enable Secure Boot in BIOS"
            echo "================================================="
            echo ""
            
            # Create helper script for post-reboot
            cat > /tmp/omarchy-sb-enroll.sh << 'ENROLL_EOF'
#!/bin/bash
echo "Enrolling Omarchy secure boot keys..."
sudo sbctl enroll-keys -m -f
sudo sbctl status
echo "Keys enrolled! Now reboot and enable Secure Boot in BIOS."
ENROLL_EOF
            chmod +x /tmp/omarchy-sb-enroll.sh
            
            echo "After clearing keys in BIOS, run: /tmp/omarchy-sb-enroll.sh"
        else
            echo "Secure boot keys already exist"
            sudo sbctl status
        fi
    else
        echo "Skipping secure boot setup"
    fi
else
    echo "Secure boot tools not found"
fi
