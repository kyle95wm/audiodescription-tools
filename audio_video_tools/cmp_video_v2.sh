#!/bin/bash

set -euo pipefail
mkdir -p "cmp"

HEIGHT=720
INPUT=""
ENABLE_SMPTE=0
ORIGINAL_QUALITY=0
NO_PROXY_APPEND=0

for arg in "$@"; do
  case "$arg" in
    --fhd)
      HEIGHT=1080
      ;;
    --smpte)
      ENABLE_SMPTE=1
      ;;
    --original-quality)
      ORIGINAL_QUALITY=1
      ;;
    --no-proxy-append|--npa)
      NO_PROXY_APPEND=1
      ;;
    --all)
      INPUT="--all"
      ;;
    *)
      INPUT="$arg"
      ;;
  esac
done

get_video_fps() {
  local input="$1"
  local fps_raw
  fps_raw="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$input" 2>/dev/null | head -n 1)"

  if [ -z "$fps_raw" ]; then
    echo "24"
    return
  fi

  if [[ "$fps_raw" == */* ]]; then
    awk -F'/' '{ if ($2 == 0) print "24"; else printf "%.6f", $1 / $2 }' <<< "$fps_raw"
  else
    echo "$fps_raw"
  fi
}

pick_audio_stream() {
  local input="$1"

  local rows
  rows="$(ffprobe -v error -select_streams a \
    -show_entries stream=index,channels:stream_tags=language \
    -of csv=p=0 "$input" 2>/dev/null || true)"

  if [ -z "$rows" ]; then
    echo "1 2"
    return
  fi

  local chosen
  chosen="$(echo "$rows" | awk -F',' 'tolower($3)=="eng" {print; exit}')"
  if [ -z "$chosen" ]; then
    chosen="$(echo "$rows" | awk -F',' 'tolower($3)=="en" {print; exit}')"
  fi
  if [ -z "$chosen" ]; then
    chosen="$(echo "$rows" | head -n 1)"
  fi

  echo "$chosen" | awk -F',' '{print $1, $2}'
}

compress_file() {
  local input_file="$1"

  if [ ! -f "$input_file" ]; then
    echo "File not found: $input_file"
    return 1
  fi

  local filename base output_file
  filename="$(basename "$input_file")"
  base="${filename%.*}"

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    if [ "$ENABLE_SMPTE" -eq 1 ]; then
      output_file="cmp/${base}_smpte_oq.mp4"
    else
      output_file="cmp/${base}_oq.mp4"
    fi
  elif [ "$NO_PROXY_APPEND" -eq 1 ]; then
    output_file="cmp/${base}.mp4"
  elif [ "$HEIGHT" -eq 1080 ]; then
    output_file="cmp/${base}_proxy_fhd.mp4"
  else
    output_file="cmp/${base}_proxy.mp4"
  fi

  if [ -f "$output_file" ]; then
    echo "Skipping $input_file (proxy exists)"
    return 0
  fi

  local a_stream ch
  read -r a_stream ch < <(pick_audio_stream "$input_file")

  local vf_filter
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    vf_filter=""
  else
    vf_filter="scale=-1:${HEIGHT}"
  fi

  if [ "$ENABLE_SMPTE" -eq 1 ]; then
    local fps drawtext_filter
    fps="$(get_video_fps "$input_file")"
    drawtext_filter="drawtext=timecode='00\\:00\\:00\\:00':timecode_rate=${fps}:fontsize=h/30:fontcolor=white@0.55:box=1:boxcolor=black@0.22:boxborderw=2:shadowx=1:shadowy=1:shadowcolor=black@0.7:x=w-tw-w*0.02:y=h-th-h*0.03"
    if [ -n "$vf_filter" ]; then
      vf_filter="${vf_filter},${drawtext_filter}"
    else
      vf_filter="$drawtext_filter"
    fi
    echo "  SMPTE overlay enabled (timecode_rate=${fps})"
  fi

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "Creating original-quality encode (audio stream 0:${a_stream}): $input_file → $output_file"
  else
    echo "Creating ${HEIGHT}p proxy (${ch}ch, audio stream 0:${a_stream}): $input_file → $output_file"
  fi

  local audio_args=()
  local video_args=()
  local filter_args=()

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    # Keep video quality high and re-encode audio at high quality for compatibility.
    audio_args=( -c:a aac -b:a 128k )
    video_args=( -c:v libx264 -crf 12 -preset slow -fps_mode passthrough )
  else
    if [ "${ch:-2}" -ge 6 ]; then
      audio_args=(
        -filter:a "pan=stereo|FL=0.707*FL+0.707*FC+0.707*BL+0.707*SL+0.5*LFE|FR=0.707*FR+0.707*FC+0.707*BR+0.707*SR+0.5*LFE"
        -ac 2
      )
    else
      audio_args=( -ac 2 )
    fi
    audio_args+=( -c:a aac -b:a 128k )
    video_args=( -c:v libx264 -crf 18 -preset veryfast -tune fastdecode -pix_fmt yuv420p -fps_mode passthrough )
  fi

  if [ -n "$vf_filter" ]; then
    filter_args=( -vf "$vf_filter" )
  fi

  ffmpeg -hide_banner -loglevel warning -stats \
    -sn \
    -i "$input_file" \
    -map 0:v:0 -map "0:${a_stream}" \
    "${filter_args[@]}" \
    "${video_args[@]}" \
    "${audio_args[@]}" \
    "$output_file"
}

if [ "$INPUT" == "--all" ]; then
  shopt -s nullglob
  for file in *.mkv *.mp4 *.mov *.m4v; do
    compress_file "$file"
  done
elif [ -n "$INPUT" ]; then
  compress_file "$INPUT"
else
  echo "Usage:"
  echo "  $0 <file>           Create 720p proxy for one video"
  echo "  $0 --all            Create 720p proxies for all videos"
  echo "  $0 --fhd <file>     Create 1080p proxy for one video"
  echo "  $0 <file> --fhd     Create 1080p proxy for one video"
  echo "  $0 --fhd --all      Create 1080p proxies for all videos"
  echo "  $0 --no-proxy-append|--npa <file>  Name proxy output cmp/<base>.mp4"
  echo "  $0 --smpte <file>   Add subtle SMPTE overlay to proxy"
  echo "  $0 --smpte --all    Add subtle SMPTE overlay to all proxies"
  echo "  $0 --smpte --original-quality <file>  Add SMPTE and preserve source quality as much as possible"
  exit 1
fi
