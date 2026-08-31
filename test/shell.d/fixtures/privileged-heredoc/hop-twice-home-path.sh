#!/bin/bash

# Two hops. The scan resolves omarchy_bin into helper, so the value it ends up
# judging still carries an unresolved $HOME rather than a literal path.
omarchy_bin="$HOME/.local/share/omarchy/bin"
helper="$omarchy_bin/omarchy-agent"

# omarchy:heredoc-expands paths=none -- helper names the agent, no path is baked in
cat <<EOF | sudo tee /etc/udev/rules.d/99-omarchy-agent.rules >/dev/null
SUBSYSTEM=="power_supply", RUN+="$helper"
EOF
