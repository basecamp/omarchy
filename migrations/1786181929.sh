echo "Give SSH commands the user-level tool paths via the PAM environment"

# SSH commands (ssh host cmd) run without a login or interactive shell, so the
# PAM environment is the only place they can inherit PATH from. Same line that
# install/config/ssh-command-path.sh writes on fresh installs; skip if PATH is
# already managed there (by us or by the user).
grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf && exit 0

sudo tee -a /etc/security/pam_env.conf >/dev/null <<'EOF'

# Omarchy: give SSH commands and other non-shell logins the user-level tool paths
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
