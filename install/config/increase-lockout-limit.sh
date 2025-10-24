# Set lockout limit to 5 failed attempts and timeout to 10 minutes
sudo sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=5 unlock_time=600|' "/etc/pam.d/system-auth"
sudo sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=5 unlock_time=600|' "/etc/pam.d/system-auth"
