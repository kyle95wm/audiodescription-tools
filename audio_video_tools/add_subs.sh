#!/bin/bash

# Usage: ./add_subtitles.sh input_video output_mkv

INPUT_VIDEO="$1"
TARGET_MKV="$2"
TEMP_SUB="extracted_sub.srt"

if [[ -z "$INPUT_VIDEO" || -z "$TARGET_MKV" ]]; then
  echo "Usage: $0 input_video output_mkv"
  exit 1
fi

echo "[📥] Extracting subtitles from: $INPUT_VIDEO"
ffmpeg -y -i "$INPUT_VIDEO" -map 0:s:0 -c:s srt "$TEMP_SUB"

if [[ ! -s "$TEMP_SUB" ]]; then
  echo "[❌] No subtitle track found or failed to convert to .srt"
  exit 1
fi

echo "[🎞️] Adding subtitles to: $TARGET_MKV"
mkvmerge -o "${TARGET_MKV%.mkv}_with_subs.mkv" "$TARGET_MKV" --language 0:eng "$TEMP_SUB"

echo "[✅] Done. Output: ${TARGET_MKV%.mkv}_with_subs.mkv"
rm "$TEMP_SUB"
