tmp=/tmp/omarchy-generated
cat >"$tmp" <<EOF
command=$HOME/.local/share/omarchy/bin/example
EOF
sudo install -m644 "${tmp}" /etc/omarchy/example.conf
