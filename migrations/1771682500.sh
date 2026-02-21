echo "Prevent SDDM password login from creating encrypted login keyring"

# Remove the encrypted login keyring if it exists (it conflicts with the passwordless Default_keyring)
rm -f "$HOME/.local/share/keyrings/login.keyring"

# Remove gnome-keyring auth/password lines from sddm PAM so password-based logins
# don't create an encrypted login keyring. Keep the session line to start the daemon,
# which will auto-unlock the passwordless Default_keyring.
sudo sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
sudo sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
