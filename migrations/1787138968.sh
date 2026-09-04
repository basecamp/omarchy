echo "Install iio-sensor-proxy on machines with an accelerometer"

# Screen auto-rotation reads the accelerometer through iio-sensor-proxy. New
# installs pick it up from install/hardware/accelerometer.sh; this covers the
# machines that were already set up before that existed.
omarchy-hw-accelerometer || exit 0

omarchy-pkg-add iio-sensor-proxy
