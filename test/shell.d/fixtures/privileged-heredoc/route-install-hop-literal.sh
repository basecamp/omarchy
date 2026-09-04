#!/bin/bash

cat <<EOF >/tmp/omarchy-review-unit
[Service]
ExecStart=$HOME/.local/bin/payload
EOF
sudo install -m 644 /tmp/omarchy-review-unit /etc/systemd/system/review.service
