echo "Ensure lockout limit is reset on reboot"

sudo sed -i '/pam_faillock\.so preauth/d' /etc/pam.d/sddm-autologin
sudo sed -i '/auth.*pam_permit\.so/a auth        required    pam_faillock.so authsucc' /etc/pam.d/sddm-autologin
