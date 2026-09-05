echo "Let the compositor and audio graph take realtime priority"

# Hyprland asks the kernel for realtime on its event thread at startup and
# PipeWire's module-rt asks for rt.prio 88. Both need RLIMIT_RTPRIO on the
# systemd user manager, which pam_limits grants to members of the realtime
# group from realtime-privileges' limits.d file. Neither the package nor the
# membership was ever installed, so both requests have been failing silently
# and every compositor and audio thread runs as SCHED_OTHER.

omarchy-pkg-add realtime-privileges

# The group is what the limits file keys on, so a machine with the package and
# without the membership is still where it started.
if ! id -nG "$USER" | tr " " "\n" | grep -qxF realtime; then
  sudo usermod -aG realtime "$USER"
fi

# pam_limits applies the limit once, when it sets up the user manager, and the
# compositor asks for realtime once, when it starts. There is one user manager
# per user rather than per session, so any other session -- a second TTY, an SSH
# login -- keeps the old one alive through a graphical logout and the new limit
# never lands. Reboot is the instruction that is always true.
echo "Reboot to pick this up: the user manager reads the new limit when it starts, and one stays alive for as long as any session does."
