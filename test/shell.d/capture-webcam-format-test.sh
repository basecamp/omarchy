#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

stub_bin="$tmp_dir/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/v4l2-ctl" <<'SH'
#!/bin/bash

case $OMARCHY_TEST_WEBCAM_FORMATS in
empty)
  exit 0
  ;;
missing)
  exit 1
  ;;
bison)
  cat <<'FMT'
ioctl: VIDIOC_ENUM_FMT
Type: Video Capture

[0]: 'MJPG' (Motion-JPEG, compressed)
	Size: Discrete 1280x720
		Interval: Discrete 0.033s (30.000 fps)
	Size: Discrete 640x360
		Interval: Discrete 0.033s (30.000 fps)
	Size: Discrete 1920x1080
		Interval: Discrete 0.033s (30.000 fps)
[1]: 'YUYV' (YUYV 4:2:2)
	Size: Discrete 1280x720
		Interval: Discrete 0.100s (10.000 fps)
	Size: Discrete 640x360
		Interval: Discrete 0.033s (30.000 fps)
	Size: Discrete 1920x1080
		Interval: Discrete 0.200s (5.000 fps)
FMT
  ;;
issue7300)
  cat <<'FMT'
ioctl: VIDIOC_ENUM_FMT
Type: Video Capture

[0]: 'MJPG' (Motion-JPEG, compressed)
	Size: Discrete 1280x720
		Interval: Discrete 0.033s (30.000 fps)
[1]: 'YUYV' (YUYV 4:2:2)
	Size: Discrete 1280x720
		Interval: Discrete 0.200s (5.000 fps)
FMT
  ;;
lowfps-small)
  cat <<'FMT'
ioctl: VIDIOC_ENUM_FMT
Type: Video Capture

[0]: 'YUYV' (YUYV 4:2:2)
	Size: Discrete 640x360
		Interval: Discrete 0.200s (5.000 fps)
[1]: 'MJPG' (Motion-JPEG, compressed)
	Size: Discrete 1280x720
		Interval: Discrete 0.033s (30.000 fps)
FMT
  ;;
yuyv-only)
  cat <<'FMT'
ioctl: VIDIOC_ENUM_FMT
Type: Video Capture

[0]: 'YUYV' (YUYV 4:2:2)
	Size: Discrete 1280x720
		Interval: Discrete 0.200s (5.000 fps)
FMT
  ;;
h264)
  cat <<'FMT'
ioctl: VIDIOC_ENUM_FMT
Type: Video Capture

[0]: 'H264' (H.264, compressed)
	Size: Discrete 1920x1080
		Interval: Discrete 0.033s (30.000 fps)
[1]: 'YUYV' (YUYV 4:2:2)
	Size: Discrete 1920x1080
		Interval: Discrete 0.033s (30.000 fps)
FMT
  ;;
esac
SH
chmod +x "$stub_bin/v4l2-ctl"

export PATH="$stub_bin:$ROOT/bin:$PATH"

assert_format() {
  local description=$1
  local fixture=$2
  local expected=$3
  local actual status=0

  actual=$(OMARCHY_TEST_WEBCAM_FORMATS=$fixture omarchy-capture-webcam-format /dev/video0) || status=$?
  [[ $status -eq 0 && $actual == "$expected" ]] ||
    fail "$description" "expected ${expected@Q}, got status=$status output=${actual@Q}"
  pass "$description"
}

assert_format "BisonCam prefers 640x360 MJPG at 30 fps over YUYV" \
  bison "video_size=640x360,framerate=30,input_format=mjpeg"

assert_format "issue #7300 camera requests 1280x720 MJPG instead of YUYV@5" \
  issue7300 "video_size=1280x720,framerate=30,input_format=mjpeg"

assert_format "skips a 5 fps 640x360 YUYV mode when 1280x720 MJPG@30 exists" \
  lowfps-small "video_size=1280x720,framerate=30,input_format=mjpeg"

assert_format "YUYV-only 720p still sets size, fps and input_format" \
  yuyv-only "video_size=1280x720,framerate=5,input_format=yuyv422"

assert_format "H264 wins over YUYV at the same 30 fps size" \
  h264 "video_size=1920x1080,framerate=30,input_format=h264"

assert_format "empty v4l2 output keeps the previous framerate=30 default" \
  empty "framerate=30"

assert_format "a missing v4l2-ctl still prints framerate=30" \
  missing "framerate=30"

status=0
usage=$(omarchy-capture-webcam-format 2>/dev/null) || status=$?
((status != 0)) && [[ -z $usage ]] ||
  fail "missing device argument exits non-zero" "status=$status output=${usage@Q}"
pass "missing device argument exits non-zero"

grep -q 'omarchy-capture-webcam-format "$WEBCAM_DEVICE"' "$ROOT/bin/omarchy-capture-screenrecording" ||
  fail "screenrecording overlay uses the webcam format helper"
pass "screenrecording overlay uses the webcam format helper"
