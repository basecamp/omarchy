echo "Enable VAAPI hardware video decoding/encoding in Chromium and Brave for h265 and other codecs"

add_flag() {
  local file=$1
  local flag=$2

  [[ -f $file ]] || return
  grep -q "$flag" "$file" && return

  if grep -q "^--enable-features=" "$file"; then
    sed -i "s/^--enable-features=\(.*\)$/--enable-features=\1,$flag/" "$file"
  else
    echo "--enable-features=$flag" >>"$file"
  fi
}

for conf in chromium-flags.conf brave-flags.conf; do
  add_flag "$HOME/.config/$conf" "VaapiVideoDecodeLinuxGL"
  add_flag "$HOME/.config/$conf" "VaapiVideoEncoder"
done
