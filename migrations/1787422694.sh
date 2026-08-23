echo "Silence the lid gate's per-sudo journal noise"

# The clamshell gate in front of pam_fprintd is a predicate, not an action:
# exit 1 means "lid is open, carry on to pam_fprintd". pam_exec has no notion
# of that and logs every non-zero exit as "failed: exit code 1", so machines
# that took the gate from 1784818437 (or an older omarchy-setup-security-
# fingerprint) write an error to the journal on every open-lid sudo and pkexec.
#
# quiet only suppresses the terminal echo; quiet_log suppresses the log write.
# Both are stock pam_exec options (quiet_log since Linux-PAM 1.5.2).

for pam in /etc/pam.d/sudo /etc/pam.d/polkit-1; do
  if [[ -f $pam ]] &&
    grep -q 'omarchy-hw-laptop-closed' "$pam" &&
    ! grep -q 'quiet_log.*omarchy-hw-laptop-closed' "$pam"; then
    sudo sed -i '/omarchy-hw-laptop-closed/s/pam_exec\.so quiet /pam_exec.so quiet quiet_log /' "$pam"
  fi
done
