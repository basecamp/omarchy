echo "Remove VAAPI GL video feature flags from Chromium-based browser configs to prevent crashing on some machines"

remove_chromium_vaapi_features() {
  local file=$1

  [[ -f $file ]] || return 0

  sed -i --follow-symlinks \
    -e '/^--enable-features=/ s/VaapiVideoDecodeLinuxGL//g' \
    -e '/^--enable-features=/ s/VaapiVideoEncoder//g' \
    -e '/^--enable-features=/ s/,,*/,/g' \
    -e '/^--enable-features=/ s/=,/=/' \
    -e '/^--enable-features=/ s/,$//' \
    -e '/^--enable-features=$/d' \
    "$file"
}

for flags_file in "$HOME"/.config/{chromium,chrome,google-chrome,google-chrome-beta,google-chrome-unstable,brave,brave-beta,brave-nightly,brave-origin-beta,microsoft-edge-stable,microsoft-edge-beta,microsoft-edge-dev,vivaldi-stable,vivaldi-snapshot,opera,opera-beta,opera-developer}-flags.conf; do
  remove_chromium_vaapi_features "$flags_file"
done
