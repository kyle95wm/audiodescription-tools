#!/bin/bash

set -euo pipefail
mkdir -p "cmp"

HEIGHT=720
INPUT=""
ENABLE_SMPTE=0
ORIGINAL_QUALITY=0
NO_PROXY_APPEND=0
PRESERVE_CONTAINER=0
AUTO_CONFIRM=0
PREFLIGHT_PROCESS_COUNT=0
PREFLIGHT_SKIP_COUNT=0
INPUT_FILES=()

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
    --preserve-container)
      PRESERVE_CONTAINER=1
      ;;
    --yes|--force)
      AUTO_CONFIRM=1
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
  fps_raw="$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=nw=1:nk=1 "$input" 2>/dev/null | head -n 1 || true)"

  if [ -z "$fps_raw" ]; then
    echo "24"
    return
  fi

  if [[ "$fps_raw" == */* ]]; then
    awk -F'/' '{ if ($2 == 0) print "24"; else printf "%.6f", $1 / $2 }' <<< "$fps_raw"
  elif awk -v value="$fps_raw" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/) }'; then
    echo "$fps_raw"
  else
    echo "24"
  fi
}

get_duration_seconds() {
  local input="$1"
  ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input" 2>/dev/null | head -n 1 || true
}

get_video_dimensions() {
  local input="$1"
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$input" 2>/dev/null | head -n 1 || true
}

get_file_size_bytes() {
  local input="$1"
  wc -c < "$input" 2>/dev/null | tr -d '[:space:]' || true
}

format_bytes() {
  local bytes="${1:-}"

  if [ -z "$bytes" ]; then
    echo "unknown"
    return
  fi

  awk -v bytes="$bytes" '
    BEGIN {
      split("B KB MB GB TB", units, " ")
      value = bytes + 0
      unit = 1
      while (value >= 1024 && unit < 5) {
        value /= 1024
        unit++
      }
      if (unit == 1) {
        printf "%.0f %s", value, units[unit]
      } else {
        printf "%.1f %s", value, units[unit]
      }
    }
  '
}

format_duration() {
  local seconds="${1:-}"

  if [ -z "$seconds" ] || ! awk -v value="$seconds" 'BEGIN { exit !(value ~ /^[0-9]+([.][0-9]+)?$/) }'; then
    echo "unknown"
    return
  fi

  awk -v value="$seconds" '
    BEGIN {
      total = int(value + 0.5)
      hours = int(total / 3600)
      minutes = int((total % 3600) / 60)
      secs = total % 60
      printf "%02d:%02d:%02d", hours, minutes, secs
    }
  '
}

yes_no() {
  if [ "${1:-0}" -eq 1 ]; then
    echo "yes"
  else
    echo "no"
  fi
}

describe_mode() {
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "Original-quality re-encode"
  else
    echo "${HEIGHT}p proxy"
  fi
}

describe_video_settings() {
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "libx264 CRF 12, preset slow, source resolution"
  else
    echo "libx264 CRF 18, preset veryfast, scale to ${HEIGHT}p"
  fi
}

describe_output_container() {
  if [ "$PRESERVE_CONTAINER" -eq 1 ]; then
    echo "preserve source extension"
  else
    echo "mp4"
  fi
}

describe_output_naming() {
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    if [ "$ENABLE_SMPTE" -eq 1 ]; then
      echo "<base>_smpte_oq<ext>"
    else
      echo "<base>_oq<ext>"
    fi
  elif [ "$NO_PROXY_APPEND" -eq 1 ]; then
    echo "<base><ext>"
  elif [ "$HEIGHT" -eq 1080 ]; then
    echo "<base>_proxy_fhd<ext>"
  else
    echo "<base>_proxy<ext>"
  fi
}

get_output_file() {
  local input_file="$1"
  local filename base input_ext output_ext

  filename="$(basename "$input_file")"
  base="${filename%.*}"
  if [ "$base" = "$filename" ]; then
    input_ext=""
  else
    input_ext=".${filename##*.}"
  fi

  output_ext=".mp4"
  if [ "$PRESERVE_CONTAINER" -eq 1 ] && [ -n "$input_ext" ]; then
    output_ext="$input_ext"
  fi

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    if [ "$ENABLE_SMPTE" -eq 1 ]; then
      echo "cmp/${base}_smpte_oq${output_ext}"
    else
      echo "cmp/${base}_oq${output_ext}"
    fi
  elif [ "$NO_PROXY_APPEND" -eq 1 ]; then
    echo "cmp/${base}${output_ext}"
  elif [ "$HEIGHT" -eq 1080 ]; then
    echo "cmp/${base}_proxy_fhd${output_ext}"
  else
    echo "cmp/${base}_proxy${output_ext}"
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

estimate_output_size_bytes() {
  local input_file="$1"
  local duration source_size dims source_w source_h fps target_width
  local estimate_bytes

  duration="$(get_duration_seconds "$input_file")"
  if ! awk -v value="$duration" 'BEGIN { exit !((value + 0) > 0) }'; then
    echo ""
    return
  fi

  source_size="$(get_file_size_bytes "$input_file")"
  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "$source_size"
    return
  fi

  dims="$(get_video_dimensions "$input_file")"
  if [[ "$dims" == *x* ]]; then
    source_w="${dims%x*}"
    source_h="${dims#*x}"
  else
    source_w=$((HEIGHT * 16 / 9))
    source_h="$HEIGHT"
  fi

  fps="$(get_video_fps "$input_file")"
  target_width="$(awk -v sw="$source_w" -v sh="$source_h" -v th="$HEIGHT" '
    BEGIN {
      if ((sh + 0) <= 0) {
        width = th * 16 / 9
      } else {
        width = sw * th / sh
      }
      width = int((width + 1) / 2) * 2
      if (width < 2) {
        width = 2
      }
      printf "%.0f", width
    }
  ')"

  estimate_bytes="$(awk -v tw="$target_width" -v th="$HEIGHT" -v fps="$fps" -v duration="$duration" '
    BEGIN {
      bpp = 0.075
      video_kbps = tw * th * fps * bpp / 1000
      if (th <= 720) {
        if (video_kbps < 1200) video_kbps = 1200
        if (video_kbps > 4500) video_kbps = 4500
      } else {
        if (video_kbps < 2500) video_kbps = 2500
        if (video_kbps > 9500) video_kbps = 9500
      }
      total_kbps = video_kbps + 128
      printf "%.0f", duration * total_kbps * 1000 / 8
    }
  ')"

  echo "$estimate_bytes"
}

collect_input_files() {
  INPUT_FILES=()

  if [ "$INPUT" = "--all" ]; then
    shopt -s nullglob
    INPUT_FILES=( *.mkv *.mp4 *.mov *.m4v )
    shopt -u nullglob
  elif [ -n "$INPUT" ]; then
    INPUT_FILES=( "$INPUT" )
  fi
}

validate_input_files() {
  local input_file
  local missing=0

  for input_file in "${INPUT_FILES[@]}"; do
    if [ ! -f "$input_file" ]; then
      echo "File not found: $input_file"
      missing=1
    fi
  done

  if [ "$missing" -eq 1 ]; then
    exit 1
  fi
}

print_preflight_summary() {
  local input_file output_file source_bytes duration estimate_bytes output_bytes
  local total_source_bytes=0
  local total_estimated_bytes=0
  local total_duration_seconds=0
  local rounded_duration
  local status

  PREFLIGHT_PROCESS_COUNT=0
  PREFLIGHT_SKIP_COUNT=0

  echo
  echo "Overview"
  echo "--------"
  echo "Mode: $(describe_mode)"
  echo "Video: $(describe_video_settings)"
  echo "Audio: AAC 128k stereo"
  echo "SMPTE overlay: $(yes_no "$ENABLE_SMPTE")"
  echo "Preserve container: $(yes_no "$PRESERVE_CONTAINER")"
  echo "Output container: $(describe_output_container)"
  echo "Output naming: $(describe_output_naming)"
  echo "Matched files: ${#INPUT_FILES[@]}"
  echo

  for input_file in "${INPUT_FILES[@]}"; do
    output_file="$(get_output_file "$input_file")"
    source_bytes="$(get_file_size_bytes "$input_file")"
    duration="$(get_duration_seconds "$input_file")"
    estimate_bytes="$(estimate_output_size_bytes "$input_file")"
    status="CREATE"

    if [ -f "$output_file" ]; then
      status="SKIP"
      PREFLIGHT_SKIP_COUNT=$((PREFLIGHT_SKIP_COUNT + 1))
      output_bytes="$(get_file_size_bytes "$output_file")"
    else
      PREFLIGHT_PROCESS_COUNT=$((PREFLIGHT_PROCESS_COUNT + 1))
      output_bytes=""
    fi

    if [ -n "$source_bytes" ]; then
      total_source_bytes=$((total_source_bytes + source_bytes))
    fi

    if awk -v value="$duration" 'BEGIN { exit !((value + 0) > 0) }'; then
      rounded_duration="$(awk -v value="$duration" 'BEGIN { printf "%.0f", value }')"
      total_duration_seconds=$((total_duration_seconds + rounded_duration))
    fi

    if [ "$status" = "CREATE" ] && [ -n "$estimate_bytes" ]; then
      total_estimated_bytes=$((total_estimated_bytes + estimate_bytes))
    fi

    echo "[$status] $input_file"
    echo "  source: $(format_bytes "$source_bytes") | duration: $(format_duration "$duration")"
    echo "  output: $output_file"

    if [ "$status" = "SKIP" ] && [ -n "$output_bytes" ]; then
      echo "  output size: $(format_bytes "$output_bytes") (existing)"
    elif [ -n "$estimate_bytes" ]; then
      echo "  estimated output: $(format_bytes "$estimate_bytes")"
    else
      echo "  estimated output: unknown"
    fi
  done

  echo
  echo "Summary"
  echo "-------"
  echo "To process: $PREFLIGHT_PROCESS_COUNT file(s)"
  echo "Skipping existing outputs: $PREFLIGHT_SKIP_COUNT file(s)"
  echo "Total input duration: $(format_duration "$total_duration_seconds")"
  echo "Total source size: $(format_bytes "$total_source_bytes")"

  if [ "$PREFLIGHT_PROCESS_COUNT" -gt 0 ]; then
    echo "Estimated new output size: $(format_bytes "$total_estimated_bytes")"
  fi

  if [ "$ORIGINAL_QUALITY" -eq 1 ]; then
    echo "Estimate note: original-quality size estimates are based on source file sizes and may vary with content."
  else
    echo "Estimate note: proxy size estimates are rough and based on duration, frame rate, target resolution, and 128k AAC audio."
  fi

  echo
}

confirm_preflight() {
  local reply

  print_preflight_summary

  if [ "$PREFLIGHT_PROCESS_COUNT" -eq 0 ]; then
    echo "Nothing to process."
    exit 0
  fi

  if [ "$AUTO_CONFIRM" -eq 1 ]; then
    echo "Auto-confirm enabled; starting processing."
    return
  fi

  if [ ! -t 0 ]; then
    echo "Interactive confirmation is required. Re-run with --yes to skip the prompt."
    exit 1
  fi

  printf "Proceed with processing? [y/N] "
  if ! read -r reply; then
    echo
    echo "Cancelled."
    exit 0
  fi

  case "$reply" in
    [Yy]|[Yy][Ee][Ss])
      ;;
    *)
      echo "Cancelled."
      exit 0
      ;;
  esac
}

compress_file() {
  local input_file="$1"

  if [ ! -f "$input_file" ]; then
    echo "File not found: $input_file"
    return 1
  fi

  local output_file
  output_file="$(get_output_file "$input_file")"

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

if [ "$INPUT" != "--all" ] && [ -z "$INPUT" ]; then
  echo "Usage:"
  echo "  $0 <file>           Create 720p proxy for one video"
  echo "  $0 --all            Create 720p proxies for all videos"
  echo "  $0 --fhd <file>     Create 1080p proxy for one video"
  echo "  $0 <file> --fhd     Create 1080p proxy for one video"
  echo "  $0 --fhd --all      Create 1080p proxies for all videos"
  echo "  $0 --no-proxy-append|--npa <file>  Name proxy output cmp/<base>.mp4"
  echo "  $0 --preserve-container <file>  Keep the source container extension"
  echo "  $0 --smpte <file>   Add subtle SMPTE overlay to proxy"
  echo "  $0 --smpte --all    Add subtle SMPTE overlay to all proxies"
  echo "  $0 --smpte --original-quality <file>  Add SMPTE and preserve source quality as much as possible"
  echo "  $0 --yes <file>     Show overview, skip prompt, and start immediately"
  exit 1
fi

collect_input_files

if [ "${#INPUT_FILES[@]}" -eq 0 ]; then
  echo "No matching video files found."
  exit 0
fi

validate_input_files
confirm_preflight

for file in "${INPUT_FILES[@]}"; do
  compress_file "$file"
done
