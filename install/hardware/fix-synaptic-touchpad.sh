# Enable Synaptics InterTouch for confirmed touchpads if not already loaded
#
# Only when modprobe can resolve psmouse for the running kernel, and never
# fatally. Installs run this under arch-chroot, where uname -r still names the
# live ISO's kernel while /lib/modules holds the target's -- the two differ on
# every machine that is not a T2 Mac, so modprobe failed with "Module psmouse
# not found in directory /lib/modules/<live kernel>" and took the whole install
# down with it. Asking modprobe itself first (-qn resolves a module without
# loading it) keeps that mismatch quiet, and the warning below covers every
# other reason it declines. An optional touchpad improvement must not be able to
# halt an install.
#
# Loading a module into the live kernel does nothing for the installed system
# either way, so this only takes effect when it runs on the booted machine.
# Persisting the switch instead would mean writing options psmouse
# synaptics_intertouch=1 to /etc/modprobe.d, which forces the SMBus transport
# past the kernel's own allowlist on every touchpad merely named "synaptics" in
# /proc/bus/input/devices -- a wider change than this one, and not one to make
# blind.
if grep -qi synaptics "${OMARCHY_SYNAPTIC_INPUT_DEVICES:-/proc/bus/input/devices}" \
   && ! lsmod | grep -q '^psmouse' \
   && modprobe -qn psmouse; then
  modprobe psmouse synaptics_intertouch=1 ||
    echo "Warning: could not enable Synaptics InterTouch on psmouse" >&2
fi
