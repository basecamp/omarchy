# Strix Halo (Ryzen AI Max+ 395) has broken VA-API video decode/encode in Chromium-based
# browsers, so force software video decoding. Matched on CPU only; the GPU portion of the
# model name varies by configuration.

if grep -qiE 'ryzen ai max[^0-9]*395' /proc/cpuinfo; then
  add_chromium_vaapi_flags() {
    local file=$1
    [[ -f $file ]] || return 0

    local flags=(
      "--disable-features=VaapiVideoDecoder,VaapiVideoDecodeLinuxGL,UseChromeOSDirectVideoDecoder"
      "--disable-accelerated-video-decode"
      "--disable-accelerated-video-encode"
    )

    for flag in "${flags[@]}"; do
      grep -qxF -- "$flag" "$file" || echo "$flag" >>"$file"
    done
  }

  add_chromium_vaapi_flags ~/.config/chromium-flags.conf
  add_chromium_vaapi_flags ~/.config/brave-flags.conf
fi
