echo "Enable Vulkan GPU acceleration for Voxtype dictation"

# omarchy-voxtype-install used to run `voxtype setup gpu --enable` without sudo,
# which failed to repoint the root-owned /usr/bin/voxtype symlink and was
# swallowed by `|| true`, leaving the CPU backend selected on Vulkan hardware.

voxtype_bin="${OMARCHY_VOXTYPE_BIN:-/usr/bin/voxtype}"

omarchy-cmd-present voxtype || exit 0
omarchy-hw-vulkan || exit 0

# Only repair installs still on a CPU Whisper backend; a Vulkan or ONNX target
# means GPU setup already ran or the user deliberately switched engines.
case $(basename "$(readlink -f "$voxtype_bin")") in
  voxtype-avx2 | voxtype-avx512) ;;
  *) exit 0 ;;
esac

sudo voxtype setup gpu --enable

# Pick up the Vulkan binary without waiting for the next login.
if systemctl --user is-active --quiet voxtype; then
  systemctl --user restart voxtype
fi
