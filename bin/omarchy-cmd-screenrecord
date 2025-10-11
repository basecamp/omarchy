#!/bin/bash

[[ -f ~/.config/user-dirs.dirs ]] && source ~/.config/user-dirs.dirs
OUTPUT_DIR="${OMARCHY_SCREENRECORD_DIR:-${XDG_VIDEOS_DIR:-$HOME/Videos}}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  notify-send "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
  exit 1
fi

SCOPE=""
AUDIO="false"
WEBCAM="false"

for arg in "$@"; do
  case "$arg" in
    --with-audio) AUDIO="true" ;;
    --with-webcam) WEBCAM="true" ;;
    output|region) SCOPE="$arg" ;;
  esac
done

cleanup_webcam() {
  pkill -f "WebcamOverlay" 2>/dev/null
}

start_webcam_overlay() {
  cleanup_webcam

  # Get monitor scale
  local scale=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .scale')

  # Target width (base 360px, scaled to monitor)
  local target_width=$(awk "BEGIN {printf \"%.0f\", 360 * $scale}")

  # Try preferred 16:9 resolutions in order, use first available
  local preferred_resolutions=("640x360" "1280x720" "1920x1080")
  local video_size_arg=""
  local available_formats=$(v4l2-ctl --list-formats-ext -d /dev/video0 2>/dev/null)

  for resolution in "${preferred_resolutions[@]}"; do
    if echo "$available_formats" | grep -q "$resolution"; then
      video_size_arg="-video_size $resolution"
      break
    fi
  done

  ffplay -f v4l2 $video_size_arg -framerate 30 /dev/video0 \
    -vf "scale=${target_width}:-1" \
    -window_title "WebcamOverlay" \
    -noborder \
    -fflags nobuffer -flags low_delay \
    -probesize 32 -analyzeduration 0 \
    -loglevel quiet &
  sleep 1
}

start_screenrecording() {
  local filename="$OUTPUT_DIR/screenrecording-$(date +'%Y-%m-%d_%H-%M-%S').mp4"
  local audio_args=""

  # Merge audio tracks into one - separate tracks only play one at a time in most players
  [[ "$AUDIO" == "true" ]] && audio_args="-a default_output|default_input"

  gpu-screen-recorder -w "$@" -f 60 -c mp4 -o "$filename" $audio_args &
  toggle_screenrecording_indicator
}

stop_screenrecording() {
  pkill -SIGINT -f "gpu-screen-recorder"  # SIGINT required to save video properly

  # Wait a maximum of 5 seconds to finish before hard killing
  local count=0
  while pgrep -f "gpu-screen-recorder" >/dev/null && [ $count -lt 50 ]; do
    sleep 0.1
    count=$((count + 1))
  done

  if pgrep -f "gpu-screen-recorder" >/dev/null; then
    pkill -9 -f "gpu-screen-recorder"
    cleanup_webcam
    notify-send "Screen recording error" "Recording process had to be force-killed. Video may be corrupted." -u critical -t 5000
  else
    cleanup_webcam
    notify-send "Screen recording saved to $OUTPUT_DIR" -t 2000
  fi
  toggle_screenrecording_indicator
}

toggle_screenrecording_indicator() {
  pkill -RTMIN+8 waybar
}

screenrecording_active() {
  pgrep -f "gpu-screen-recorder" >/dev/null || pgrep -x slurp >/dev/null || pgrep -f "WebcamOverlay" >/dev/null
}

if screenrecording_active; then
  if pgrep -x slurp >/dev/null; then
    pkill -x slurp 2>/dev/null
  elif pgrep -f "WebcamOverlay" >/dev/null && ! pgrep -f "gpu-screen-recorder" >/dev/null; then
    cleanup_webcam
  else
    stop_screenrecording
  fi
elif [[ "$SCOPE" == "output" ]]; then
  [[ "$WEBCAM" == "true" ]] && start_webcam_overlay

  if ! output=$(slurp -o -f "%o"); then
    [[ "$WEBCAM" == "true" ]] && cleanup_webcam
    exit 1
  fi

  if [[ -z "$output" ]]; then
    notify-send "Error" "Could not detect monitor" -u critical
    [[ "$WEBCAM" == "true" ]] && cleanup_webcam
    exit 1
  fi

  start_screenrecording "$output"
else
  [[ "$WEBCAM" == "true" ]] && start_webcam_overlay

  scale=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .scale')

  if ! region=$(slurp -f "%wx%h+%x+%y"); then
    [[ "$WEBCAM" == "true" ]] && cleanup_webcam
    exit 1
  fi

  if [[ "$region" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
    w=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[1]} * $scale}")
    h=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[2]} * $scale}")
    x=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[3]} * $scale}")
    y=$(awk "BEGIN {printf \"%.0f\", ${BASH_REMATCH[4]} * $scale}")
    scaled_region="${w}x${h}+${x}+${y}"
  else
    scaled_region="$region"
  fi

  start_screenrecording region -region "$scaled_region"
fi
