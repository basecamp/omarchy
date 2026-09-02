echo "Install the PipeWire realtime scheduling provider on Apple Silicon"

# PipeWire asks rtkit for realtime priority; without it audio threads run at
# normal priority and drop out under load. The x86_64 package set already
# carries it, the Arch Linux ARM install an Apple Silicon Mac started from
# does not.
omarchy-hw-apple-silicon || exit 0
omarchy-pkg-add rtkit
