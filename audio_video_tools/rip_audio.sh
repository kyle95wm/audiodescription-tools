#!/bin/bash
# set -x  # Uncomment for debug mode

# Check if file exists
file_exists() {
    if [ ! -f "$1" ]; then
        echo "File not found: $1"
        exit 1
    fi
}

# Check for input file
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

CHANNEL_LAYOUT=$(ffprobe -v error -select_streams "a:$STREAM_INDEX" \
-show_entries stream=channel_layout -of default=nw=1:nk=1 "$VIDEO_FILE")

if [[ -z "$CHANNEL_LAYOUT" ]]; then
    CHANNEL_LAYOUT="$(ffprobe -v error -select_streams "a:$STREAM_INDEX" \
    -show_entries stream=channels -of default=nw=1:nk=1 "$VIDEO_FILE")ch"
fi

RAW_LAYOUT="$CHANNEL_LAYOUT"
CHANNEL_LAYOUT=$(echo "$CHANNEL_LAYOUT" | tr -d '()')  # Clean parentheses

BASENAME=$(basename "$VIDEO_FILE")
BASENAME="${BASENAME%.*}"
BASENAME_CLEAN=$(echo "$BASENAME" | tr ' ' '_' | tr -cd '[:alnum:]_-')

OUTPUT_DIR="./output"
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="${OUTPUT_DIR}/${BASENAME_CLEAN}_${CHANNEL_LAYOUT}.${EXT}"

read -p "Do you want to specify a different output format? (y/N): " CHOICE

if [[ "$CHOICE" =~ ^[Yy]$ ]]; then
    read -p "Enter the desired audio format (e.g., ac3, mp3, wav): " AUDIO_FORMAT
    EXT="$AUDIO_FORMAT"
    OUTPUT_FILE="${OUTPUT_DIR}/${BASENAME_CLEAN}_${CHANNEL_LAYOUT}.${EXT}"

    if [[ "$AUDIO_FORMAT" == "wav" ]]; then
        ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a pcm_s24le "$OUTPUT_FILE"
    else
        ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a "$AUDIO_FORMAT" "$OUTPUT_FILE"
    fi
else
    if [[ "$EXT" == "wav" ]]; then
        ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a pcm_s24le "$OUTPUT_FILE"
    else
        ffmpeg -i "$VIDEO_FILE" -map "0:a:$STREAM_INDEX" -c:a copy "$OUTPUT_FILE"
    fi
fi

echo "Extracted audio stream saved as $OUTPUT_FILE"

# Optional 5.1 channel splitting
if [[ "$EXT" == "wav" && ( "$RAW_LAYOUT" == "5.1" || "$RAW_LAYOUT" == "5.1(side)" ) ]]; then
    read -p "Do you also want to split this 5.1 WAV into individual mono WAV files? (y/N): " SPLIT_CHOICE
    if [[ "$SPLIT_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Splitting 5.1 WAV into mono stems..."

        # Adjust suffixes based on layout
        if [[ "$RAW_LAYOUT" == "5.1(side)" ]]; then
            SR_L=SL
            SR_R=SR
        else
            SR_L=BL
            SR_R=BR
        fi

        ffmpeg -i "$OUTPUT_FILE" -filter_complex \
        "channelsplit=channel_layout=5.1[FL][FR][FC][LFE][${SR_L}][${SR_R}]" \
        -map "[FL]" "$OUTPUT_DIR/${BASENAME_CLEAN}_FL.wav" \
        -map "[FR]" "$OUTPUT_DIR/${BASENAME_CLEAN}_FR.wav" \
        -map "[FC]" "$OUTPUT_DIR/${BASENAME_CLEAN}_C.wav" \
        -map "[LFE]" "$OUTPUT_DIR/${BASENAME_CLEAN}_LFE.wav" \
        -map "[${SR_L}]" "$OUTPUT_DIR/${BASENAME_CLEAN}_SL.wav" \
        -map "[${SR_R}]" "$OUTPUT_DIR/${BASENAME_CLEAN}_SR.wav"
        
        echo "Mono channel files saved in $OUTPUT_DIR"
    fi
fi
