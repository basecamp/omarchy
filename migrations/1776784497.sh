echo "Remove resume boost feature"

if [[ -f /usr/lib/systemd/system-sleep/resume-boost ]]; then
  sudo rm /usr/lib/systemd/system-sleep/resume-boost
fi
