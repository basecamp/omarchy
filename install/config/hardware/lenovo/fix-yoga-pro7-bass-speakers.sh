# Fix bass speakers on Lenovo Yoga Pro 7 14IAH10
# The ALC287 codec needs a pin quirk to route audio to both AMP speakers.
# Without this quirk, only one speaker works and bass output is missing.
# Reference: https://wiki.archlinux.org/title/Lenovo_Yoga_9i_2022_(14AiPI7)

if omarchy-hw-lenovo-yoga-pro7-bass; then
  sudo tee /etc/modprobe.d/lenovo-yoga-pro7-bass.conf <<'EOF'
options snd-sof-intel-hda-generic hda_model=alc287-yoga9-bass-spk-pin
EOF
fi
