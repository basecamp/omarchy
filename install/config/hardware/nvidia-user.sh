envs="$HOME/.config/hypr/envs.lua"
[[ -f $envs ]] || exit 0

if lspci | grep -qi 'nvidia'; then
  if omarchy-hw-nvidia-gsp && ! grep -q 'NVIDIA (Turing+ with GSP firmware)' "$envs"; then
    cat >>"$envs" <<'EOF'

-- NVIDIA (Turing+ with GSP firmware)
hl.env("NVD_BACKEND", "direct")
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
  elif omarchy-hw-nvidia-without-gsp && ! grep -q 'NVIDIA (Maxwell/Pascal/Volta without GSP firmware)' "$envs"; then
    cat >>"$envs" <<'EOF'

-- NVIDIA (Maxwell/Pascal/Volta without GSP firmware)
hl.env("NVD_BACKEND", "egl")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
EOF
  fi
fi
