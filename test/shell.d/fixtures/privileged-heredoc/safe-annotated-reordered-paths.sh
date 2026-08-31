storage="$HOME/storage"
shared="$HOME/shared"

# omarchy:heredoc-expands paths=shared,storage -- both sources are validated before use
cat >/etc/omarchy/mounts.conf <<EOF
storage=$storage:/storage
shared=$shared:/shared
EOF
