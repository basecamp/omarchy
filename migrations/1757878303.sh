echo "Adding shell check to mise activate in config/uwsm/env"

sed -i '5s|if command -v mise &> /dev/null; then|if command -v mise \&> /dev/null \&\& [[ "$SHELL" == "/bin/bash" ]]; then|'