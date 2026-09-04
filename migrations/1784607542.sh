echo "Disable Chromium's Wayland Vulkan WebGPU interop to prevent browser crashes"

add_webgpu_adapter_flag() {
  local file=$1
  [[ -f $file && -r $file && -w $file ]] || return 0
  grep -Fxq -- "--use-webgpu-adapter=opengles" "$file" && return 0
  [[ -n $(tail -c1 "$file") ]] && echo >>"$file"
  echo "--use-webgpu-adapter=opengles" >>"$file"
}

for flags_file in "$HOME"/.config/{chromium,chrome,google-chrome,google-chrome-beta,google-chrome-unstable,microsoft-edge-stable,microsoft-edge-beta,microsoft-edge-dev,vivaldi-stable,vivaldi-snapshot,opera,opera-beta,opera-developer}-flags.conf; do
  add_webgpu_adapter_flag "$flags_file"
done

brave_flags="$HOME/.config/brave-flags.conf"
brave_origin_flags="$HOME/.config/brave-origin-flags.conf"
brave_origin_beta_flags="$HOME/.config/brave-origin-beta-flags.conf"

if [[ -f $brave_flags ]] && {
  [[ -L $brave_origin_flags && $(readlink -f "$brave_flags") == $(readlink -f "$brave_origin_flags") ]] ||
  [[ -L $brave_origin_beta_flags && $(readlink -f "$brave_flags") == $(readlink -f "$brave_origin_beta_flags") ]]
}; then
  echo "Skip Brave flags shared with Brave Origin until its wrapper supports multiple flags"
else
  add_webgpu_adapter_flag "$brave_flags"
  add_webgpu_adapter_flag "$brave_origin_flags"
  add_webgpu_adapter_flag "$brave_origin_beta_flags"
fi
