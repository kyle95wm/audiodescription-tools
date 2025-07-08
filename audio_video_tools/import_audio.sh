#!/usr/bin/env bash

set -e

INPUT_VIDEO="$1"
INPUT_AUDIO="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/import_audio.conf"

# Check for updates
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ℹ️] No config file found. Proceeding without config."
else
  echo "[🔧] Loading config: $CONFIG_FILE"
  source "$CONFIG_FILE"
fi

read -p $'\nChoose audio codec (wav/aac/eac3) [default=eac3]: ' AUDIO_CODEC
AUDIO_CODEC="${AUDIO_CODEC:-eac3}"

echo -e "\nRecommended bitrates: 224k (stereo), 640k (5.1 surround)"
read -p "Set audio bitrate (e.g., 224k) [leave blank for smart default]: " AUDIO_BITRATE

read -p $'\nWhat would you like to do with the audio? (add/replace) [default=replace]: ' AUDIO_ACTION
AUDIO_ACTION="${AUDIO_ACTION:-replace}"

read -p $'\nSelect container (mp4/mkv) [default=mkv]: ' CONTAINER
CONTAINER="${CONTAINER:-mkv}"

read -p $'\nStrip marker chapters from audio? (Y/N) [default=Y]: ' STRIP_MARKERS
STRIP_MARKERS="${STRIP_MARKERS:-Y}"

read -p $'\nCopy subtitle tracks from original video? (Y/N) [default=Y]: ' COPY_SUBS
COPY_SUBS="${COPY_SUBS:-Y}"

OUTPUT_FILE="./$(basename "${INPUT_VIDEO%.*}")_${AUDIO_ACTION}d_audio.${CONTAINER}"
TMP_DIR=$(mktemp -d)
MAP_OPTIONS="-map 0:v:0"

# Select original audio based on replace/add mode
if [ "$AUDIO_ACTION" == "replace" ]; then
  MAP_OPTIONS+=" -map 1:a:0"
else
  MAP_OPTIONS+=" -map 0:a -map 1:a:0"
fi

# Add subtitle streams if requested
if [ "$COPY_SUBS" == "Y" ]; then
  ffprobe -v error -select_streams s -show_entries stream=index -of csv=p=0 "$INPUT_VIDEO" | while read -r IDX; do
    ffmpeg -y -i "$INPUT_VIDEO" "$TMP_DIR/sub${IDX}.srt" < /dev/null
    SUBS+=("$TMP_DIR/sub${IDX}.srt")
  done
fi

CMD=(ffmpeg -y -i "$INPUT_VIDEO" -i "$INPUT_AUDIO")

# Inject subtitle inputs
for SUB in "${SUBS[@]}"; do
  CMD+=(-i "$SUB")
done

CMD+=(
  $MAP_OPTIONS
  -c:v copy
  -c:a "$AUDIO_CODEC"
)

[ -n "$AUDIO_BITRATE" ] && CMD+=(-b:a "$AUDIO_BITRATE")

# Map subtitle streams and set language
for i in "${!SUBS[@]}"; do
  CMD+=(-map $((i + 2)):s:0 -c:s:$i srt -metadata:s:s:$i language=eng)
done

CMD+=("$OUTPUT_FILE")

echo -e "\n🎬 ${INPUT_VIDEO} ⇄ ${INPUT_AUDIO} → ${OUTPUT_FILE}"
"${CMD[@]}"

echo -e "\n✅ Single mux complete."

# Optional cleanup
rm -r "$TMP_DIR"
