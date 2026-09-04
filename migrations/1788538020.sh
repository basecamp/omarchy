echo "Enable OpenVINO acceleration for Voxtype on Intel NPU systems"

if omarchy-cmd-present voxtype && omarchy-hw-npu; then
  omarchy-pkg-add voxtype-bin openvino-genai openvino-intel-npu-plugin
  voxtype setup onnx --enable
  voxtype setup npu --enable
  voxtype setup systemd
  systemctl --user restart voxtype
fi
