OMARCHY_DESCRIPTION="Lockout Limit"

omarchy_install() {
  # Increase lockout limit to 10 and decrease timeout to 2 minutes
  sudo sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' "/etc/pam.d/system-auth"
  sudo sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' "/etc/pam.d/system-auth"
}

omarchy_verify() {
  [[ -f /etc/pam.d/system-auth ]] || add_error "PAM system-auth file missing"

  if [[ -f /etc/pam.d/system-auth ]]; then
    grep -q "pam_faillock.so.*deny=10" /etc/pam.d/system-auth || add_error "Faillock deny limit not set to 10"
    grep -q "pam_faillock.so.*unlock_time=120" /etc/pam.d/system-auth || add_error "Faillock unlock time not set to 120"
  fi
}
