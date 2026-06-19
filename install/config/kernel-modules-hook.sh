# On Fedora, kernel module management is handled natively by the kernel and akmods/dkms.
# The Arch-specific linux-modules-cleanup.service does not exist on Fedora.
# Fedora's dnf automatically handles old module cleanup via kernel-install.
# Nothing to do here.
echo "Kernel module management: handled natively by Fedora (no extra setup needed)"
