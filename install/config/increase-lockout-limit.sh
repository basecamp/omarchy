# The faillock.conf side ships via the omarchy-settings etc-overrides
# (deny = 10). The two PAM file edits below remain a script because
# /etc/pam.d/system-auth and /etc/pam.d/sddm-autologin are upstream-owned
# and the changes are insertions, not full-file overrides.

# Increase lockout limit to 10 and decrease timeout to 2 minutes
sudo sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' "/etc/pam.d/system-auth"
sudo sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' "/etc/pam.d/system-auth"

# Ensure lockout limit is reset on restart.
# Delete BOTH the preauth and authsucc pam_faillock lines before re-adding
# authsucc, so re-running the installer doesn't duplicate the authsucc line.
sudo sed -i '/pam_faillock\.so preauth/d'  /etc/pam.d/sddm-autologin
sudo sed -i '/pam_faillock\.so authsucc/d' /etc/pam.d/sddm-autologin
sudo sed -i '/auth.*pam_permit\.so/a auth        required    pam_faillock.so authsucc' /etc/pam.d/sddm-autologin
