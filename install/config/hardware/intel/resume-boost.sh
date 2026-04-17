# Boost CPU performance for 10 seconds after resume on Intel systems.
# The powersave governor with balance_power EPP is slow to ramp frequency
# after long suspends, causing noticeable sluggishness on wake.

if omarchy-hw-intel; then
  sudo mkdir -p /usr/lib/systemd/system-sleep
  sudo install -m 0755 -o root -g root "$OMARCHY_PATH/default/systemd/system-sleep/resume-boost" /usr/lib/systemd/system-sleep/
fi
