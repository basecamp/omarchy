# Install MIPI camera support for Intel IPU7 hardware

# Match on the sensor being fitted, not merely declared. A DSDT can carry an
# OVTI08F4 node for a camera the machine was never built with -- the HP
# EliteBook X G2i declares one alongside its actual OV05C10, with _STA 0 -- and
# matching the HID alone installs CamHAL, icamerasrc and v4l2-relayd for a sensor
# that is not there. On that machine it also collides with the camera package
# that does own the hardware, which conflicts with this one, and the install
# fails.
if omarchy-hw-acpi-present OVTI08F4; then
  omarchy-pkg-add intel-ipu7-camera
fi
