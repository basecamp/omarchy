# Give the user 5 instead of 3 tries to fat finger their password before lockout
echo "Defaults passwd_tries=5" | sudo tee /etc/sudoers.d/passwd-tries
sudo chmod 440 /etc/sudoers.d/passwd-tries
