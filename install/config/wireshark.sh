if getent group wireshark >/dev/null; then
  sudo usermod -aG wireshark ${USER}
fi
