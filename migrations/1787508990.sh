echo "Wire up the T1 Touch Bar display-bind fix for existing installs"

: "${OMARCHY_PATH:=/usr/share/omarchy}"
: "${OMARCHY_INSTALL:=$OMARCHY_PATH/install}"
# shellcheck source=../install/hardware/apple/t1-touchbar-disp-bind.sh
source "$OMARCHY_INSTALL/hardware/apple/t1-touchbar-disp-bind.sh"

if ! t1_touchbar_disp_needed; then
  exit 0
fi
if t1_touchbar_disp_installed; then
  exit 0
fi

t1_touchbar_disp_install
