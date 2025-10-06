OMARCHY_DESCRIPTION="Framework 13 AMD Audio Input Fix"

should_run() {
  AMD_AUDIO_CARD=$(pactl list cards 2>/dev/null | grep -B20 "Family 17h/19h" | grep "Name: " | awk '{print $2}' || true)
  [[ -n "$AMD_AUDIO_CARD" ]]
}

omarchy_install() {
  should_run || return 0

  pactl set-card-profile "$AMD_AUDIO_CARD" "HiFi (Mic1, Mic2, Speaker)" 2>/dev/null || true
}

omarchy_verify() {
  should_run || return 2

  pactl list cards | grep -A10 "$AMD_AUDIO_CARD" | grep -q "Active Profile:" || add_error "AMD audio profile not configured"
}
