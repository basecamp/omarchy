echo "Keep systemd-oomd from breaking app launches with a private procfs"

# Replace the old unconditional app.slice drop-in with generator output. A
# reload also removes previously generated candidacy when PID 1 is hidden.
systemctl --user daemon-reload >/dev/null 2>&1 || true
