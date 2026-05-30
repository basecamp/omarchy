echo "Gate sudo fingerprint behind lid state (skip fingerprint when the laptop lid is closed)"

# Desktops / machines without an ACPI lid button are left completely untouched.
lid_present=false
for f in /proc/acpi/button/lid/*/state; do
  [[ -e "$f" ]] && lid_present=true
done
$lid_present || exit 0

# Only relevant if sudo actually uses fingerprint and isn't already guarded.
if grep -q pam_fprintd.so /etc/pam.d/sudo && ! grep -q omarchy-lid-open /etc/pam.d/sudo; then
  # Install / refresh the lid-state helper used by pam_exec.
  sudo tee /usr/local/bin/omarchy-lid-open >/dev/null <<'EOF'
#!/bin/bash
# omarchy:summary=Exit 0 if the laptop lid is open (used by PAM to gate fingerprint auth)
for f in /proc/acpi/button/lid/*/state; do
  [[ -r "$f" ]] || continue
  if grep -q open "$f"; then exit 0; else exit 1; fi
done
exit 0
EOF
  sudo chmod 755 /usr/local/bin/omarchy-lid-open

  # Insert the guard immediately above the existing pam_fprintd line.
  sudo sed -i '/pam_fprintd\.so/i auth    [success=ignore default=1] pam_exec.so quiet /usr/local/bin/omarchy-lid-open' /etc/pam.d/sudo
fi
