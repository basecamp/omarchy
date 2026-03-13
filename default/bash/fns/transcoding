# Transcode a video to a good-balance 1080p that's great for sharing online
transcode-video-1080p() {
  ffmpeg -i "$1" -vf scale=1920:1080 -c:v libx264 -preset fast -crf 23 -c:a copy "${1%.*}-1080p.mp4"
}

# Transcode a video to a good-balance 4K that's great for sharing online
transcode-video-4K() {
  ffmpeg -i "$1" -c:v libx265 -preset slow -crf 24 -c:a aac -b:a 192k "${1%.*}-optimized.mp4"
}

# Transcode any image to JPG image that's great for shrinking wallpapers
img2jpg() {
  img="$1"
  shift

  magick "$img" "$@" -quality 95 -strip "${img%.*}-converted.jpg"
}

# Transcode any image to a small JPG (max 1080px wide) that's great for sharing online
img2jpg-small() {
  img="$1"
  shift

  magick "$img" "$@" -resize 1080x\> -quality 95 -strip "${img%.*}-small.jpg"
}

# Transcode any image to a medium JPG (max 1800px wide) that's great for sharing online
img2jpg-medium() {
  img="$1"
  shift

  magick "$img" "$@" -resize 1800x\> -quality 95 -strip "${img%.*}-medium.jpg"
}

# Transcode any image to compressed-but-lossless PNG
img2png() {
  img="$1"
  shift

  magick "$img" "$@" -strip -define png:compression-filter=5 \
    -define png:compression-level=9 \
    -define png:compression-strategy=1 \
    -define png:exclude-chunk=all \
    "${img%.*}-optimized.png"
}
