echo "Increase faillock attempts to 10"
sudo sed -i 's/^# *deny = .*/deny = 10/' /etc/security/faillock.conf
