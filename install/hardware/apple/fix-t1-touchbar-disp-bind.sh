# The T1 Touch Bar's virtual display sub-device (1D6B:0301) does not
# reliably win its own auto-bind race even once the driver stack is
# loaded — the bar shows icons but stays dark. See
# t1-touchbar-disp-bind.sh for the mechanism.

: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=t1-touchbar-disp-bind.sh
source "$OMARCHY_INSTALL/hardware/apple/t1-touchbar-disp-bind.sh"

if ! t1_touchbar_disp_needed; then
  return 0
fi
if t1_touchbar_disp_installed; then
  return 0
fi

echo "Wiring up the T1 Touch Bar display-bind fix"
t1_touchbar_disp_install
