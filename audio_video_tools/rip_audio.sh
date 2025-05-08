#!/bin/bash
# set -x  # Uncomment for debug mode

WAV_FORMAT=""  # placeholder

file_exists() {
    if [ ! -f "$1" ]; then
        echo "File not found: $1"
        exit 1
    fi
}

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <video file>"
    exit 1
fi

VIDEO_FILE="$1"
file_exists "$VIDEO_FILE"

echo "Listing all audio streams:"
ffprobe -v error -select_streams a -show_entries stream=index,codec_name,channel_layout \
-of csv=p=0 "$VIDEO_FILE" | awk -F',' '{
    printf "  [%d] Stream #0:%s — %s, %s\n", NR-1, $1, $2, $3
}'

read -p "Enter the audio stream index to extract (e.g., 1 for second audio stream): " STREAM_INDEX
if ! [[ "$STREAM_INDEX" =~ ^[0-9]+$ ]]; then
    echo "Invalid stream index: $STREAM_INDEX"
    exit 1
fi

ORIGINAL_FORMAT=$(ffprobe -v error -select_streams "a:$STREAM_INDEX" \
-show_entries stream=codec_name -of default=nw=1:nk=1 "$VIDEO_FILE")

CHANNEL_LAYOUT=$(ffprobe -v error -select_streams "a:$STREAM_INDEX" \
-show_entries stream=channel_layout -of default=nw=1:nk=1 "$VIDEO_FILE")

if [[ -z "$CHANNEL_LAYOUT" ]]; then
    CHANNEL_LAYOUT="$(ffprobe -v error -select_streams "a:$STREAM_INDEX" \
    -show_entries stream=channels -of default=nw=1:nk=1 "$VIDEO_FILE")ch"
fi

RAW_LAYOUT="$CHANNEL_LAYOUT"
CHANNEL_LAYOUT=$(echo "$CHANNEL_LAYOUT" | tr -d '()')

BASENAME=$(basename "$VIDEO_FILE")
BASENAME="${BASENAME%.*}"
BASENAME_CLEAN=$(echo "$BASENAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')

OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

# === FORMAT DECISION LOGIC ===

if [[ "$CHANNEL_LAYOUT" =~ ^5\.1 ]]; then
    # Auto-pick WAV, switch to CAF if long
    EXT="wav"
    DURATION=$(ffprobe -v error -select_streams a:$STREAM_INDEX \
    -show_entries stream=duration -of default=nw=1:nk=1 "$VIDEO_FILE" | cut -d'.' -f1)
    if [[ "$DURATION" -gt 5400 ]]; then
        echo "[INFO] 5.1 stream is longer than 90 minutes — switching to CAF"
        EXT="caf"
    else
        echo "[INFO] 5.1 stream detected — exporting as 24-bit WAV"
    fi
else
    # For non-5.1 streams, detect format
    case "$ORIGINAL_FORMAT" in
        aac) EXT="aac" ;;
        mp3) EXT="mp3" ;;
        ac3) EXT="ac3" ;;
        eac3) EXT="eac3" ;;
        flac) EXT="flac" ;;
        vorbis) EXT="ogg" ;;
        opus) EXT="opus" ;;
        dts) EXT="dts" ;;
        wav) EXT="wav" ;;
        *) EXT="m4a" ;;
    esac

    echo "Detected audio format: $ORIGINAL_FORMAT ($EXT)"

    # Ask user if they want to override
    read -p "Do you want to specify a different output format? (y/N): " CHOICE

    if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
        read -p "Enter the desired audio format (e.g., ac3, mp3, wav): " AUDIO_FORMAT
        EXT="$AUDIO_FORMAT"
    fi
fi

OUTPUT_FILE="${OUTPUT_DIR}/${BASENAME_CLEAN}_${CHANNEL_LAYOUT}.${EXT}"

# === EXPORT ===

if [[ "$EXT" == "wav" || "$EXT" == "caf" ]]; then
    # Use RF64 for WAV to avoid size limit issues
    if [[ "$EXT" == "wav" ]]; then
        ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a pcm_s24le -rf64 always "$OUTPUT_FILE"
    else
        ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a pcm_s24le "$OUTPUT_FILE"
    fi
else
    ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a copy "$OUTPUT_FILE"
fi

echo "Extracted audio stream saved as $OUTPUT_FILE"
