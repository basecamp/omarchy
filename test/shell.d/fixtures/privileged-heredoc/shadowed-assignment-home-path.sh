#!/bin/bash

# The name is introduced with a packaged root-owned value and then reassigned to
# one under the user's home. Judging the first assignment would read this as the
# path it no longer holds.
target=/usr/share/omarchy/bin/agent
target="$HOME/.local/share/omarchy/bin/agent"

# omarchy:heredoc-expands paths=none -- target is the packaged agent path under /usr
cat <<EOF | sudo tee /etc/systemd/system/omarchy-agent.service >/dev/null
[Service]
ExecStart=$target
EOF
