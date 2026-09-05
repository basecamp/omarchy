echo "Keep the Apple USB SD card reader alive after suspend"

# The 2013–2015 Apple USB Card Reader stays powered off after sleep. Install-time
# setup now writes a kernel quirk, udev pin, sleep hook, and acpi_call. Existing
# Macs only get that on omarchy update via this migration.
if omarchy-hw-apple-sd-reader; then
  source "$OMARCHY_PATH/install/hardware/apple/fix-sd-card-reader.sh"
fi
