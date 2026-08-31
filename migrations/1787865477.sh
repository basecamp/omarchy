echo "Drop the default input group grant, which allowed unprivileged keylogging"

# Membership of `input` gives raw read/write access to /dev/input/event*: any
# process running as the user can capture keystrokes and synthesize input. The
# blanket grant is unnecessary: the Xbox-controller and ydotool installers add
# the group themselves when those features are deliberately installed.
#
# Preserve membership where one of those opt-in features is present; removing
# it there would break the feature the user chose to install.
if id -nG "$USER" | grep -qw input; then
  if pacman -Qq xpadneo-dkms &>/dev/null || pacman -Qq ydotool &>/dev/null; then
    echo "Keeping $USER in the input group: controller or ydotool support is installed."
  else
    sudo gpasswd -d "$USER" input >/dev/null
    echo "Removed $USER from the input group. Log out and back in to apply."
    omarchy-state set reboot-required
  fi
fi
