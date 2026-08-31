# omarchy:heredoc-expands paths=none -- the positional argument is a scalar
sudo tee /etc/omarchy/example.conf <<EOF
argument=$1
command=$HOME/.local/share/omarchy/bin/example
EOF
