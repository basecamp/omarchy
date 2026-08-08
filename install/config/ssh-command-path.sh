# SSH commands (ssh host cmd) run without a login or interactive shell, so on
# Arch the PAM environment is the only place they can inherit PATH from. Add
# the user-level tool paths there so remote tools (herdr, editors, agent CLIs)
# find mise-managed installs. @{HOME} expands per-user from passwd. Keep the
# directories in sync with default/bash/env-bootstrap.
if ! grep -qE '^PATH[[:space:]]' /etc/security/pam_env.conf; then
  cat >>/etc/security/pam_env.conf <<'EOF'

# Omarchy: give SSH commands and other non-shell logins the user-level tool paths
PATH DEFAULT=/usr/local/sbin:/usr/local/bin:/usr/bin:@{HOME}/.local/share/mise/shims:@{HOME}/.local/bin
EOF
fi
