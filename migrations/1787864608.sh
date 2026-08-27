echo "Add cargo bin to the Omarchy PAM PATH for SSH commands"

# Fresh installs get the cargo-aware line from install/config/ssh-command-path.sh.
# Existing installs still have the legacy line from migrations/1786181929.sh; the
# install script skips any existing PATH, so upgrade those exact Omarchy-managed
# lines here and leave custom PAM PATH configuration alone.
pam="/etc/security/pam_env.conf"
legacy="PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin"
updated="PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin:@{HOME}/.cargo/bin"

[[ -f $pam ]] || exit 0
grep -qxF -- "$updated" "$pam" && exit 0
grep -qxF -- "$legacy" "$pam" || exit 0

tmp=$(mktemp)
awk -v legacy="$legacy" -v updated="$updated" '
  $0 == legacy { print updated; next }
  { print }
' "$pam" >"$tmp"
sudo cp -- "$tmp" "$pam"
rm -f "$tmp"
