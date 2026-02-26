echo "Apply system performance optimizations for development workloads"

# Apply system performance optimizations for existing installations
echo "Configuring system performance optimizations..."

# Run the system performance configuration script
bash $OMARCHY_PATH/install/config/system-performance.sh

# Apply kernel parameters immediately (they will also apply on next boot)
echo "Applying kernel parameters..."
sudo sysctl --system >/dev/null 2>&1 || true

echo "System performance optimizations applied successfully"
echo "Note: Some optimizations may require a logout/login or reboot to take full effect"
