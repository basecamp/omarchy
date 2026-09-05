# Prevent password-based SDDM logins from creating an encrypted login keyring
# that conflicts with Omarchy's passwordless default keyring behavior. The ISO
# owns autologin/session state because it knows whether the target is encrypted.
# Strip auth/password *and* session auto_start — leaving session alone still
# unlocks/creates a login keyring (omacom/omarchy#9235).
if [[ -f /etc/pam.d/sddm ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
  sed -i '/-session.*pam_gnome_keyring\.so.*auto_start/d' /etc/pam.d/sddm
fi

if [[ -f /etc/pam.d/sddm-autologin ]]; then
  sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm-autologin
  sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm-autologin
  sed -i '/-session.*pam_gnome_keyring\.so.*auto_start/d' /etc/pam.d/sddm-autologin
fi
