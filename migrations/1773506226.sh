echo "Enable GPU in voxtype if Vulkan is available"

if omarchy-cmd-present voxtype; then
  if compgen -G "/usr/share/vulkan/icd.d/*.json" >/dev/null; then
    echo "Vulkan is available, enabling GPU in voxtype"
    voxtype setup gpu --enable || true
  fi

  # see https://github.com/peteonrails/voxtype/commit/ce6e9919cbe54cb8808dcb3cdd3bcb3260d7b900
  # earlier versions of voxtype hard-coded the non-GPU backend in the systemd service file,
  # so we need to re-run setup to update it to use /usr/bin/voxtype (the symlink)
  voxtype setup systemd

  systemctl --user restart voxtype
  omarchy-restart-waybar
fi
