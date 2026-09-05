# T1 Touch Bar Macs export an IIO ALS via apple_ib_als. Session auto-brightness
# is the user unit omarchy-als-brightness.service (enabled at first-run / migrate).
# This leaf only records the hardware so the installer log shows why.

product_name="$(cat /sys/class/dmi/id/product_name 2>/dev/null)"
if [[ $product_name =~ MacBookPro13,[23]|MacBookPro14,[23] ]]; then
  echo "Detected T1 MacBook Pro; ambient-light brightness follows the ALS when it is bound"
fi
