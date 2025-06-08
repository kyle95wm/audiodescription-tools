#!/bin/bash

# Usage: ./script.sh <video> <wav1> [wav2] <output> [--dry-run]

if [[ $# -lt 3 ]]; then
  echo "Usage: $0 <video> <wav1> [wav2] <output> [--dry-run]"
  exit 1
fi

VIDEO="$1"
WAV1="$2"
WAV2=""
OUT=""
DRY_RUN="false"

if [[ "$3" == *.wav ]]; then
  WAV2="$3"
  OUT="$4"
  [[ "$5" == "--dry-run" ]] && DRY_RUN="true"
else
  OUT="$3"
  [[ "$4" == "--dry-run" ]] && DRY_RUN="true"
fi

# Base FFmpeg command
CMD=(ffmpeg -y -i "$VIDEO")

# Add audio inputs
CMD+=(-i "$WAV1")
[[ -n "$WAV2" ]] && CMD+=(-i "$WAV2")

# Start mapping: always map video from input 0
CMD+=(-map 0:v:0)

# Detect channel count for WAV1
CH1=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels \
    -of default=noprint_wrappers=1:nokey=1 "$WAV1")

if [[ "$CH1" == "6" ]]; then
  CMD+=(-map 1:a:0 -c:a:0 eac3 -b:a:0 640k -metadata:s:a:0 title="English - Audio Description 5.1")
elif [[ "$CH1" == "2" ]]; then
  CMD+=(-map 1:a:0 -c:a:0 eac3 -b:a:0 192k -metadata:s:a:0 title="English - Audio Description Stereo")
else
  echo "Unsupported channel count in $WAV1: $CH1"
  exit 1
fi
CMD+=(-metadata:s:a:0 language=eng)

# If a second WAV is supplied, assume stereo fallback
if [[ -n "$WAV2" ]]; then
  CMD+=(-map 2:a:0 -c:a:1 eac3 -b:a:1 192k -metadata:s:a:1 language=eng -metadata:s:a:1 title="English - Audio Description Stereo")
fi

CMD+=(-c:v copy "$OUT.mkv")

if [[ "$DRY_RUN" == "true" ]]; then
  echo "🎬 Command to execute:"
  echo "${CMD[@]}"
else
  echo "🚀 Muxing into $OUT.mkv..."
  "${CMD[@]}"
  echo "✅ Done."
fi
