# `>|` is a plain redirect with noclobber overridden, not a redirect into a pipe.
cat >|/etc/omarchy/agent.conf <<EOF
helper=$HOME/.local/share/omarchy/bin/omarchy-agent
EOF
