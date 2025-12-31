# Give the user 10 instead of 3 tries to fat finger their password before lockout
echo "Defaults passwd_tries=10" | sudo tee /etc/sudoers.d/passwd-tries
sudo chmod 440 /etc/sudoers.d/passwd-tries

# Set for hyprlock too
sudo sed -i 's/^# *deny = .*/deny = 10/' /etc/security/faillock.conf
