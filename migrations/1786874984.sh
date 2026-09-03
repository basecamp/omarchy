echo "Install AMD ROCm SMI on systems with an AMD GPU"

rocm_smi_script="$OMARCHY_PATH/install/hardware/amd/rocm-smi.sh"

[[ -f $rocm_smi_script ]] || exit 0
bash -euo pipefail "$rocm_smi_script"
