echo "Update polkit policy to yield to fingerprint and fido2"
# If fprint exists in polkit, it was wrong and needs reset
if [ -f /etc/pam.d/polkit-1 ] && grep -Fq 'pam_fprintd.so' /etc/pam.d/polkit-1; then
  sudo tee /etc/pam.d/polkit-1 >/dev/null <<'EOF'
auth      sufficient pam_fprintd.so
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
fi

# If fido2 is in sudo, it won't be in polkit either way
if grep -q pam_u2f.so /etc/pam.d/sudo && [ -f /etc/pam.d/polkit-1 ] && ! grep -q 'pam_u2f.so' /etc/pam.d/polkit-1; then
  sudo sed -i '1i auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2' /etc/pam.d/polkit-1
elif grep -q pam_u2f.so /etc/pam.d/sudo && [ ! -f /etc/pam.d/polkit-1 ]; then
  sudo tee /etc/pam.d/polkit-1 >/dev/null <<'EOF'
auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2
auth      required pam_unix.so

account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so
EOF
fi
