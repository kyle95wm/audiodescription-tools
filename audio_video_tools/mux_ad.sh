#!/bin/bash

# Usage:
# ./mux_ad.sh <video> <wav1> [wav2] <output name without extension> [--dry-run]

if [[ "$1" == "-h" || "$1" == "--help" || $# -lt 3 ]]; then
  echo "Usage: $0 <video> <wav1> [wav2] <output name (no ext)> [--dry-run]"
  exit 1
fi

video="$1"
wav1="$2"
shift 2

# Assume next arg is wav2 if it ends in .wav or .WAV
if [[ "$1" == *.wav || "$1" == *.WAV ]]; then
  wav2="$1"
  shift
else
  wav2=""
fi

output="$1"
shift

dry_run=false
if [[ "$1" == "--dry-run" ]]; then
  dry_run=true
fi

# Build base FFmpeg command
cmd=(ffmpeg -y -i "$video" -i "$wav1")

if [[ -n "$wav2" ]]; then
  cmd+=(-i "$wav2")
fi

cmd+=(
  -map 0:v:0
  -map 1:a:0
  -c:v copy
  -c:a:0 eac3
  -b:a:0 640k
  -metadata:s:a:0 language=eng
  -metadata:s:a:0 title="Audio Description 5.1"
)

if [[ -n "$wav2" ]]; then
  cmd+=(
    -map 2:a:0
    -c:a:1 eac3
    -b:a:1 192k
    -metadata:s:a:1 language=eng
    -metadata:s:a:1 title="Audio Description Stereo"
  )
fi

cmd+=("${output}.mkv")

if $dry_run; then
  echo "🎬 Command to execute:"
  printf '%q ' "${cmd[@]}"
  echo
else
  echo "🚀 Encoding to ${output}.mkv..."
  "${cmd[@]}"
  echo "✅ Done."
fi
