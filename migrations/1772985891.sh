echo "Add ROCm SMI for AMD GPU support in btop"

if omarchy-hw-amdgpu; then
  omarchy-pkg-add rocm-smi-lib
fi
