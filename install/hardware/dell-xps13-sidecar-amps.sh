# Enable the temporary sidecar amplifier workaround on the exact Dell XPS 13 model that needs it.
#
# Pacman registers a package even when its post_install scriptlet fails, so the
# apply command runs explicitly here: a failed cleanup or boot-image rebuild has
# to reach the caller rather than hide behind a successfully registered package.

if omarchy-hw-dell-xps13-sidecar-amps; then
  omarchy-pkg-add dell-xps13-sidecar-amps &&
    sudo dell-xps13-sidecar-amps-apply
fi
