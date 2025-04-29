#!/usr/bin/env bash

print_usage() {
    echo "Usage:"
    echo "  Single mux: $0 <video_file> <audio_file>"
    echo "  Batch mux:  $0 <video_folder> <audio_folder> [output_folder]"
    echo "  Audio only: $0 <audio_file> --audio-only"
    echo
    echo "Optional flags:"
    echo "  --no-config | -nc      Ignore any saved config file"
    echo "  --audio-only | -ao     Re-encode only the audio, no muxing to video"
    exit 1
}

command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found."; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found."; exit 1; }

[[ $# -lt 1 ]] && print_usage

INPUT1="$1"
INPUT2="$2"
OUTPUT_DIR="${3:-$(pwd)}"

# === Flag checks ===
NO_CONFIG=false
AUDIO_ONLY=false
for arg in "$@"; do
    [[ "$arg" == "--no-config" || "$arg" == "-nc" ]] && NO_CONFIG=true
    [[ "$arg" == "--audio-only" || "$arg" == "-ao" ]] && AUDIO_ONLY=true
done

is_directory() { [[ -d "$1" ]]; }
is_file() { [[ -f "$1" ]]; }
cleanup_temp() { [[ -f "$1" && "$1" != "$2" ]] && rm "$1"; }

# === Load config (unless skipped) ===
CONFIG_FILE=""
if [[ "$NO_CONFIG" == false ]]; then
    if [[ -f "$(dirname "$0")/import_audio.conf" ]]; then
        CONFIG_FILE="$(dirname "$0")/import_audio.conf"
    elif [[ -f "$HOME/.config/ad-tools/import_audio.conf" ]]; then
        CONFIG_FILE="$HOME/.config/ad-tools/import_audio.conf"
    fi

    if [[ -n "$CONFIG_FILE" ]]; then
        echo "[🔧] Loading config: $CONFIG_FILE"
        source "$CONFIG_FILE"
    fi
else
    echo "[⚠️] Config file loading disabled with --no-config"
fi

prompt_settings() {
    echo
    read -p "Choose audio codec (wav/aac/eac3) [default=${CODEC:-eac3}]: " c
    CODEC="${c:-$CODEC}"

    case "$CODEC" in
        wav) EXT="wav" ;;
        aac) EXT="aac" ;;
        eac3) EXT="eac3" ;;
        *) echo "❌ Invalid codec."; exit 1 ;;
    esac

    echo
    if [[ "$CODEC" == "eac3" ]]; then
        echo "Recommended bitrates for EAC3: 192k (stereo), 224k, 384k, 448k (5.1)"
    elif [[ "$CODEC" == "aac" ]]; then
        echo "Recommended bitrates for AAC: 128k (stereo), 256k (higher quality)"
    fi

    if [[ "$CODEC" != "wav" ]]; then
        read -p "Set audio bitrate (e.g., 192k) [leave blank for codec default]: " USER_BITRATE

        if [[ -z "$USER_BITRATE" ]]; then
            if [[ "$CODEC" == "eac3" ]]; then
                USER_BITRATE="192k"
                echo "[ℹ️] Defaulting to 192k for EAC3 stereo."
            elif [[ "$CODEC" == "aac" ]]; then
                USER_BITRATE="128k"
                echo "[ℹ️] Defaulting to 128k for AAC stereo."
            fi
        fi
    else
        USER_BITRATE=""
    fi

    CHANNELS=""
    
    if [[ "$AUDIO_ONLY" == false ]]; then
        echo
        read -p "What would you like to do with the audio? (add/replace) [default=${MODE:-replace}]: " m
        MODE="${m:-$MODE}"

        echo
        read -p "Select container (mp4/mkv) [default=${CONTAINER:-mkv}]: " cont
        CONTAINER="${cont:-$CONTAINER}"
        [[ "$CONTAINER" == "mp4" && "$CODEC" != "aac" ]] && echo "⚠️ Forcing MKV due to codec" && CONTAINER="mkv"

        echo
        read -p "Strip marker chapters from audio? (Y/N) [default=${STRIP_MARKERS:-Y}]: " sm
        STRIP_MARKERS="${sm:-$STRIP_MARKERS}"

        DEFAULT_FLAG=""
        if [[ "$MODE" == "add" ]]; then
            read -p "Set AD as default audio? (Y/N) [default=${SET_AD_DEFAULT:-N}]: " d
            SET_AD_DEFAULT="${d:-$SET_AD_DEFAULT}"
            [[ "$SET_AD_DEFAULT" =~ ^[Yy]$ ]] && DEFAULT_FLAG="-disposition:a:1 default"
        fi
    fi
}

process_audio_only() {
    local AUDIO="$1"
    local OUTDIR="$2"
    local BASENAME
    BASENAME=$(basename "${AUDIO%.*}")
    local OUTFILE="${OUTDIR}/${BASENAME}_reencoded.${EXT}"

    echo
    echo "🎧 Re-encoding $(basename "$AUDIO") → $OUTFILE"

    CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels \
        -of default=nokey=1:noprint_wrappers=1 "$AUDIO")
    [[ -z "$CHANNELS" ]] && CHANNELS=2

    if [[ "$CODEC" == "wav" ]]; then
        ffmpeg -y -i "$AUDIO" \
            -c:a "$CODEC" \
            -ac "$CHANNELS" \
            "$OUTFILE"
    else
        ffmpeg -y -i "$AUDIO" \
            -c:a "$CODEC" \
            -b:a "$USER_BITRATE" \
            -ac "$CHANNELS" \
            "$OUTFILE"
    fi

    echo
    echo "📋 Copy-paste this command to mux the audio with your video:"
    echo "ffmpeg -i \"your_video.mp4\" -i \"$(basename "$OUTFILE")\" -map 0:v -map 1:a -c:v copy -c:a copy \"your_new_video.mkv\""
}

process_pair() {
    local VIDEO="$1"
    local AUDIO="$2"
    local OUTDIR="$3"
    local BASENAME
    BASENAME=$(basename "${VIDEO%.*}")
    local EXTENSION
    EXTENSION="${VIDEO##*.}"

    if [[ "$EXTENSION" == "mp4" ]]; then
        CLEAN_INPUT="${OUTDIR}/${BASENAME}_cleaned_input.mkv"
        ffmpeg -y -i "$VIDEO" -map 0 -map -0:s -c copy "$CLEAN_INPUT" || {
            echo "❌ Failed to clean MP4 input. Aborting."
            return 1
        }
    else
        CLEAN_INPUT="$VIDEO"
    fi

    local MAP_CHAPTERS_FLAG=""
    if [[ "$STRIP_MARKERS" =~ ^[Yy]$ ]]; then
        HAS_MARKERS=$(ffprobe -v error -i "$AUDIO" -show_chapters | grep -q 'CHAPTER' && echo "yes" || echo "no")
        [[ "$HAS_MARKERS" == "yes" ]] && MAP_CHAPTERS_FLAG="-map_chapters -1"
    fi

    CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels \
      -of default=nokey=1:noprint_wrappers=1 "$AUDIO")
    [[ -z "$CHANNELS" ]] && CHANNELS=2

    local OUTFILE_SUFFIX="_with_AD"
    [[ "$MODE" == "replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
    local OUTFILE="${OUTDIR}/${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"

    echo
    echo "🎬 $(basename "$VIDEO") ⇄ $(basename "$AUDIO") → $OUTFILE"

    if [[ "$MODE" == "add" ]]; then
        echo
        echo "🔎 Available audio streams in original video:"
        ffprobe -v error -select_streams a \
            -show_entries stream=index,codec_name,channels,channel_layout:stream_tags=language \
            -of csv=p=0 "$VIDEO" |
            awk -F',' '{ printf "  [%s] Codec: %s | Channels: %s | Layout: %s | Lang: %s\n", $1, $2, $3, $4, $5 }'

        read -p "Enter the index of the original audio stream to preserve: " ORIGINAL_INDEX
        [[ -z "$ORIGINAL_INDEX" ]] && ORIGINAL_INDEX=0

        if [[ "$CODEC" == "wav" ]]; then
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
                -map 0:v:0 -map 0:a:$ORIGINAL_INDEX -map 1:a:0 \
                $MAP_CHAPTERS_FLAG \
                -c:v copy -c:a copy -c:a:1 "$CODEC" -b:a:1 "$USER_BITRATE" \
                -ac:a:1 "$CHANNELS" \
                $DEFAULT_FLAG \
                -metadata:s:a:0 title="Original Audio" \
                -metadata:s:a:1 title="Audio Description - English" \
                -metadata:s:a:1 language=eng \
                "$OUTFILE"
        fi
    else
        if [[ "$CODEC" == "wav" ]]; then
            ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" \
                -map 0:v:0 -map 1:a \
                $MAP_CHAPTERS_FLAG \
                -c:v copy -c:a "$CODEC" \
                -ac "$CHANNELS" \
                -metadata:s:a:0 title="Audio Description - English" \
                -metadata:s:a:0 language=eng \
                "$OUTFILE"
        else
            ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" \
                -map 0:v:0 -map 1:a \
                $MAP_CHAPTERS_FLAG \
                -c:v copy -c:a "$CODEC" -b:a "$USER_BITRATE" \
                -ac "$CHANNELS" \
                -metadata:s:a:0 title="Audio Description - English" \
                -metadata:s:a:0 language=eng \
                "$OUTFILE"
        fi
    fi

    cleanup_temp "$CLEAN_INPUT" "$VIDEO"
}

# === Main run ===
if [[ "$AUDIO_ONLY" == true ]]; then
    is_file "$INPUT1" || { echo "❌ You must provide an audio file."; exit 1; }
    prompt_settings
    process_audio_only "$INPUT1" "$(dirname "$INPUT1")"
    echo
    echo "✅ Audio-only re-encode complete."
    exit 0
fi

# Normal muxing mode
if [[ is_file "$INPUT1" && is_file "$INPUT2" ]]; then
    MODE_TYPE="single"
elif [[ is_directory "$INPUT1" && is_directory "$INPUT2" ]]; then
    MODE_TYPE="batch"
else
    echo "❌ Invalid input types."
    print_usage
fi

if [[ "$MODE_TYPE" == "single" ]]; then
    prompt_settings
    process_pair "$INPUT1" "$INPUT2" "$(dirname "$INPUT1")"
    echo
    echo "✅ Single mux complete."
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
