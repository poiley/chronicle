#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <YouTube-Live-URL>"
  exit 1
fi

URL="$1"

yt-dlp \
  --live-from-start \
  --hls-prefer-ffmpeg \
  --hls-use-mpegts \
  -f bestvideo+bestaudio \
  --merge-output-format mkv \
  -o "%(title)s.%(ext)s" \
  "$URL"
