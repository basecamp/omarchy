# Without keepalives, ssh does not notice a dead connection until TCP gives up,
# which can take hours of sitting on a hung terminal with any remote-armed
# terminal modes stuck on. Detect the drop within a minute so the shell's ssh
# wrapper can clean up and reconnect. ~/.ssh/config is read first and wins, so
# users can still override these defaults per host.
if [[ ! -f /etc/ssh/ssh_config.d/20-omarchy-keepalive.conf ]]; then
  install -d -m 755 /etc/ssh/ssh_config.d
  cat >/etc/ssh/ssh_config.d/20-omarchy-keepalive.conf <<'EOF'
# Omarchy: notice dropped connections quickly instead of hanging until TCP
# times out. Settings in ~/.ssh/config take precedence over these defaults.
Host *
  ServerAliveInterval 15
  ServerAliveCountMax 3
  ConnectTimeout 10
EOF
  chmod 644 /etc/ssh/ssh_config.d/20-omarchy-keepalive.conf
fi
