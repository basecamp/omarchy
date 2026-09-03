tmp=/tmp/omarchy-generated
copy=$tmp
cat >"$tmp" <<EOF
command=$HOME/.local/share/omarchy/bin/example
EOF
sudo install -m644 "$copy" /etc/omarchy/example.conf
