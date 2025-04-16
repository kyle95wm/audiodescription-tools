#!/usr/bin/env bash

print_usage() {
    echo "Usage:"
    echo "  Single pair mode: $0 <video_file> <audio_file>"
    echo "  Batch mode:       $0 <video_folder> <audio_folder> [output_folder]"
    exit 1
}

command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found."; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found."; exit 1; }

[[ $# -lt 2 ]] && print_usage

INPUT1="$1"
INPUT2="$2"
OUTPUT_DIR="${3:-$(pwd)}"

is_directory() { [[ -d "$1" ]]; }
is_file() { [[ -f "$1" ]]; }
cleanup_temp() { [[ -f "$1" && "$1" != "$2" ]] && rm "$1"; }

if is_file "$INPUT1" && is_file "$INPUT2"; then
    MODE="single"
elif is_directory "$INPUT1" && is_directory "$INPUT2"; then
    MODE="batch"
else
    echo "❌ Invalid input types. Both must be files or both must be folders."
    print_usage
fi

prompt_settings() {
    echo
    echo "What would you like to do with the audio?"
    echo "  1) Add as second track"
    echo "  2) Replace existing [default]"
    read -p "Enter choice [1–2]: " m
    m="${m:-2}"
    [[ "$m" == "1" ]] && MODE_CHOICE="--add" || MODE_CHOICE="--replace"

    echo
    echo "Choose audio codec:"
    echo "  1) WAV (PCM)"
    echo "  2) AAC"
    echo "  3) EAC-3 (DD+) [default]"
    read -p "Enter codec [1–3]: " c
    c="${c:-3}"
    case "$c" in
        1) CODEC="pcm_s24le"; EXT="wav" ;;
        2) CODEC="aac"; EXT="aac" ;;
        3) CODEC="eac3"; EXT="eac3" ;;
        *) echo "❌ Invalid codec."; exit 1 ;;
    esac

    echo
    echo "Select container:"
    echo "  1) MP4 (AAC only)"
    echo "  2) MKV [default]"
    read -p "Enter choice [1–2]: " cont
    cont="${cont:-2}"
    CONTAINER="mkv"
    [[ "$cont" == "1" && "$CODEC" == "aac" ]] && CONTAINER="mp4"
    [[ "$cont" == "1" && "$CODEC" != "aac" ]] && echo "⚠️  Forcing MKV due to codec." && CONTAINER="mkv"

    echo
    read -p "Strip marker chapters from audio? [Y/n]: " STRIP
    STRIP="${STRIP:-Y}"

    DEFAULT_FLAG=""
    if [[ "$MODE_CHOICE" == "--add" ]]; then
        read -p "Set AD as default audio? [y/N]: " D
        [[ "$D" =~ ^[Yy]$ ]] && DEFAULT_FLAG="-disposition:a:1 default"
    fi
}

process_pair() {
    local VIDEO="$1"
    local AUDIO="$2"
    local OUTDIR="$3"
    local BASENAME=$(basename "${VIDEO%.*}")
    local EXT="${VIDEO##*.}"

    if [[ "$EXT" == "mp4" ]]; then
        CLEAN_INPUT="${OUTDIR}/${BASENAME}_cleaned_input.mkv"
        ffmpeg -y -i "$VIDEO" -map 0 -map -0:s -c copy "$CLEAN_INPUT" || {
            echo "❌ Failed to clean MP4 input. Aborting."
            return 1
        }
    else
        CLEAN_INPUT="$VIDEO"
    fi

    local MAP_CHAPTERS_FLAG=""
    if [[ "$STRIP" =~ ^[Yy]$ ]]; then
        HAS_MARKERS=$(ffprobe -v error -i "$AUDIO" -show_chapters | grep -q 'CHAPTER' && echo "yes" || echo "no")
        [[ "$HAS_MARKERS" == "yes" ]] && MAP_CHAPTERS_FLAG="-map_chapters -1"
    fi

    CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels \
      -of default=nokey=1:noprint_wrappers=1 "$AUDIO")
    [[ -z "$CHANNELS" ]] && CHANNELS=2

    local OUTFILE_SUFFIX="_with_AD"
    [[ "$MODE_CHOICE" == "--replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
    local OUTFILE="${OUTDIR}/${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"

    echo
    echo "🎬 $(basename "$VIDEO") ⇄ $(basename "$AUDIO") → $OUTFILE"

    if [[ "$MODE_CHOICE" == "--add" ]]; then
        echo
        echo "🔎 Available audio streams in original video:"
        ffprobe -v error -select_streams a \
            -show_entries stream=index,codec_name,channels,channel_layout:stream_tags=language \
            -of csv=p=0 "$VIDEO" |
            awk -F',' '{ printf "  [%s] Codec: %s | Channels: %s | Layout: %s | Lang: %s\n", $1, $2, $3, $4, $5 }'

        read -p "Enter the index of the original audio stream to preserve: " ORIGINAL_INDEX
        [[ -z "$ORIGINAL_INDEX" ]] && ORIGINAL_INDEX=0

        ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" \
            -map 0:v:0 -map 0:a:$ORIGINAL_INDEX -map 1:a:0 \
            $MAP_CHAPTERS_FLAG \
            -c:v copy -c:a copy -c:a:1 "$CODEC" \
            -ac:a:1 "$CHANNELS" \
            $DEFAULT_FLAG \
            -metadata:s:a:0 title="Original Audio" \
            -metadata:s:a:1 title="Audio Description - English" \
            -metadata:s:a:1 language=eng \
            "$OUTFILE"
    else
        ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" \
            -map 0:v:0 -map 1:a \
            $MAP_CHAPTERS_FLAG \
            -c:v copy -c:a "$CODEC" \
            -ac "$CHANNELS" \
            -metadata:s:a:0 title="Audio Description - English" \
            -metadata:s:a:0 language=eng \
            "$OUTFILE"
    fi

    cleanup_temp "$CLEAN_INPUT" "$VIDEO"
}

if [[ "$MODE" == "single" ]]; then
    prompt_settings
    process_pair "$INPUT1" "$INPUT2" "$(dirname "$INPUT1")"
    echo
    echo "✅ Done."
    exit 0
fi

VIDEO_FILES=()
AUDIO_FILES=()
while IFS= read -r -d '' file; do VIDEO_FILES+=("$file"); done < <(find "$INPUT1" -type f -print0 | sort -z)
while IFS= read -r -d '' file; do AUDIO_FILES+=("$file"); done < <(find "$INPUT2" -type f -print0 | sort -z)

NUM_VID=${#VIDEO_FILES[@]}
NUM_AUD=${#AUDIO_FILES[@]}
PAIRS=$((NUM_VID<NUM_AUD ? NUM_VID : NUM_AUD))

echo
echo "🧾 Pairing:"
for ((i=0; i<PAIRS; i++)); do
    echo "  [$(($i+1))] $(basename "${VIDEO_FILES[$i]}") ⇄ $(basename "${AUDIO_FILES[$i]}")"
done

echo
read -p "Proceed with these $PAIRS pairs? [Y/n]: " CONFIRM
[[ "$CONFIRM" =~ ^[Nn]$ ]] && echo "Cancelled." && exit 1

prompt_settings

for ((i=0; i<PAIRS; i++)); do
    process_pair "${VIDEO_FILES[$i]}" "${AUDIO_FILES[$i]}" "$OUTPUT_DIR"
done

echo
echo "✅ Batch complete."
