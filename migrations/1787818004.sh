echo "Enable NVIDIA S0ix power management on s2idle systems"

# gpu-screen-recorder ships NVreg_PreserveVideoMemoryAllocations=1, so on
# suspend the NVIDIA driver saves VRAM to /var/tmp over GSP RPCs. A
# runtime-suspended GPU (the default on hybrid laptops) intermittently stops
# answering those RPCs (Xid 119), wedging the suspend with the lid closed —
# the laptop then overheats in the bag and drains its battery (#5274). On
# s2idle systems the driver's S0ix power management sidesteps the save
# entirely; install/hardware/nvidia.sh now gives fresh installs the same
# option.
mem_sleep="${OMARCHY_MEM_SLEEP:-/sys/power/mem_sleep}"
conf="${OMARCHY_NVIDIA_S0IX_CONF:-/etc/modprobe.d/nvidia-s0ix.conf}"

omarchy-hw-nvidia || exit 0
omarchy-cmd-present limine-mkinitcpio || exit 0
grep -q '\[s2idle\]' "$mem_sleep" 2>/dev/null || exit 0

# The conf is machine-wide, so it doubles as the completion marker: another
# user's run (or a fresh install that already wrote it) no-ops here.
[[ ! -f $conf ]] || exit 0

sudo install -Dm644 /dev/stdin "$conf" <<'EOF'
options nvidia NVreg_EnableS0ixPowerManagement=1
EOF

# The nvidia modules are early-loaded, so the option only takes effect once
# it is baked into the initramfs.
echo "Rebuilding the initramfs so the new NVIDIA module option takes effect"
sudo limine-mkinitcpio

omarchy-state set reboot-required
