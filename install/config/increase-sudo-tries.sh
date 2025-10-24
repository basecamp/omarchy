# Give the user 3 tries to enter their password before lockout
echo "Defaults passwd_tries=3" | sudo tee /etc/sudoers.d/passwd-tries
sudo chmod 440 /etc/sudoers.d/passwd-tries
