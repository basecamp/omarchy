echo "Unlock the Turbo key on Acer Predator and Nitro laptops"

# The install-time quirk only reaches machines set up after it shipped. See
# install/hardware/acer-turbo-key.sh for what predator_v4 unlocks.
conf="${OMARCHY_ACER_WMI_CONF:-/etc/modprobe.d/acer-wmi.conf}"

omarchy-hw-acer-predator || exit 0
modinfo -p acer_wmi 2>/dev/null | grep -q '^predator_v4:' || exit 0

# New installs carry this from the installer, and the first user to run the
# migration covers everyone after them. Only an active options line counts:
# someone who commented theirs out still needs this.
if grep -Eqs '^[[:space:]]*options[[:space:]]+acer_wmi[[:space:]].*predator_v4=1' "$conf"; then
  exit 0
fi

sudo mkdir -p "$(dirname "$conf")"

# Append rather than overwrite, so anything else a user keeps here survives:
# modprobe reads every options line for a module.
echo "options acer_wmi predator_v4=1" | sudo tee -a "$conf" >/dev/null

# modprobe only reads this when acer_wmi loads, and the module cannot be
# reloaded safely while the session is using its hotkeys and sensors.
omarchy-state set reboot-required
