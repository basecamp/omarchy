echo "Fix Realtek RTL8111/8168/8211/8411 ethernet adapter support for ASUS TUF and other laptops"

# Run the hardware detection script for existing installations
if [ -f "$OMARCHY_INSTALL/config/hardware/fix-realtek-r8168.sh" ]; then
  run_logged $OMARCHY_INSTALL/config/hardware/fix-realtek-r8168.sh
fi