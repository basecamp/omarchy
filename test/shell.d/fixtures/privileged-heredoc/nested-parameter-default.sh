#!/bin/bash

# omarchy:heredoc-expands paths=none -- review regression fixture
sudo tee /etc/omarchy/review.conf >/dev/null <<EOF
ExecStart=${target:-$HOME/.local/bin/payload}
EOF
