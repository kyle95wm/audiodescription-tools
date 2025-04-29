#!/usr/bin/env bash

# === Auto-updater (comment out to disable) ===
UPDATE_URL="https://raw.githubusercontent.com/kyle95wm/audiodescription-tools/main/audio_video_tools/import_audio.sh?$(date +%s)"
SCRIPT_PATH="$(realpath "$0")"

echo "[🔄] Checking for updates..."

LATEST_SCRIPT=$(mktemp)
if curl -fsSL "$UPDATE_URL" -o "$LATEST_SCRIPT"; then
    if grep -q "^#!/usr/bin/env bash" "$LATEST_SCRIPT"; then
        if ! diff -q "$SCRIPT_PATH" "$LATEST_SCRIPT" >/dev/null; then
            echo "[⬇️] Update available. Applying update..."
            cp "$LATEST_SCRIPT" "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            echo "[✅] Script updated! Re-running..."
            exec "$SCRIPT_PATH" "$@"
        else
            echo "[ℹ️] Already up-to-date."
        fi
    else
        echo "[❌] Update check failed: Downloaded file is not a valid script."
    fi
else
    echo "[⚠️] Could not check for updates. Continuing with existing script."
fi
rm -f "$LATEST_SCRIPT"
# === End auto-updater ===

print_usage() {
    echo "Usage:"
    echo "  Single mux: $0 <video_file> <audio_file1> [audio_file2] [audio_file3] ..."
    echo "  Batch mux:  $0 <video_folder> <audio_folder> [output_folder]"
    echo "  Audio only: $0 <audio_file> --audio-only"
    echo
    echo "Optional flags:"
    echo "  --no-config | -nc      Ignore saved config file"
    echo "  --audio-only | -ao     Re-encode only the audio file"
    exit 1
}

command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found."; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found."; exit 1; }

[[ $# -lt 1 ]] && print_usage

INPUT1="$1"
shift
INPUTS=("$@")

NO_CONFIG=false
AUDIO_ONLY=false
for arg in "${INPUTS[@]}"; do
    [[ "$arg" == "--no-config" || "$arg" == "-nc" ]] && NO_CONFIG=true
    [[ "$arg" == "--audio-only" || "$arg" == "-ao" ]] && AUDIO_ONLY=true
done

is_directory() { [[ -d "$1" ]]; }
is_file() { [[ -f "$1" ]]; }
cleanup_temp() { [[ -f "$1" && "$1" != "$2" ]] && rm "$1"; }

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
    echo "[⚠️] Config file loading disabled."
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
        echo "Recommended bitrates: 224k (stereo), 640k (5.1 surround)"
    elif [[ "$CODEC" == "aac" ]]; then
        echo "Recommended bitrates: 128k (stereo), 384k (5.1 surround)"
    fi

    if [[ "$CODEC" != "wav" ]]; then
        read -p "Set audio bitrate (e.g., 224k) [leave blank for smart default]: " USER_BITRATE
    else
        USER_BITRATE=""
    fi

    if [[ "$AUDIO_ONLY" == false ]]; then
        echo
        read -p "What would you like to do with the audio? (add/replace) [default=${MODE:-replace}]: " m
        MODE="${m:-$MODE}"

        echo
        read -p "Select container (mp4/mkv) [default=${CONTAINER:-mkv}]: " cont
        CONTAINER="${cont:-$CONTAINER}"
        [[ "$CONTAINER" == "mp4" && "$CODEC" != "aac" ]] && echo "⚠️ Forcing MKV due to codec" && CONTAINER="mkv"
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

    if [[ -z "$USER_BITRATE" && "$CODEC" != "wav" ]]; then
        if [[ "$CHANNELS" == "2" ]]; then
            USER_BITRATE="224k"
            echo "[ℹ️] Defaulting to 224k for stereo."
        elif [[ "$CHANNELS" -ge 6 ]]; then
            USER_BITRATE="640k"
            echo "[ℹ️] Defaulting to 640k for surround."
        else
            USER_BITRATE="224k"
        fi
    fi

    if [[ "$CODEC" == "wav" ]]; then
        ffmpeg -y -i "$AUDIO" -c:a "$CODEC" -ac "$CHANNELS" "$OUTFILE"
    else
        ffmpeg -y -i "$AUDIO" -c:a "$CODEC" -b:a "$USER_BITRATE" -ac "$CHANNELS" "$OUTFILE"
    fi

    echo
    echo "📋 To mux: ffmpeg -i your_video.mkv -i $(basename "$OUTFILE") -map 0:v -map 1:a -c:v copy -c:a copy output.mkv"
}

process_pair() {
    local VIDEO="$1"
    shift
    local AUDIO_FILES=("$@")
    local OUTDIR
    OUTDIR="$(dirname "$VIDEO")"
    local BASENAME
    BASENAME=$(basename "${VIDEO%.*}")

    echo
    echo "📝 Audio tracks to mux:"
    for f in "${AUDIO_FILES[@]}"; do
        echo "  - $(basename "$f")"
    done
    echo

    local TITLES=()
    for AUDIO in "${AUDIO_FILES[@]}"; do
        echo
        echo "For $(basename "$AUDIO"):"
        echo "  1) Original Stereo"
        echo "  2) Original 5.1"
        echo "  3) AD Stereo"
        echo "  4) AD 5.1"
        echo "  5) Commentary"
        echo "  6) Other (enter manually)"
        read -p "Select track type [1-6]: " track_type
        case "$track_type" in
            1) TITLES+=("Original Stereo") ;;
            2) TITLES+=("Original 5.1") ;;
            3) TITLES+=("Audio Description - Stereo") ;;
            4) TITLES+=("Audio Description - 5.1") ;;
            5) TITLES+=("Commentary") ;;
            6)
                read -p "Enter custom title: " custom_title
                TITLES+=("$custom_title")
                ;;
            *) TITLES+=("Unknown Track") ;;
        esac
    done

    local CMD=(ffmpeg -y -i "$VIDEO")
    for AUDIO in "${AUDIO_FILES[@]}"; do
        CMD+=(-i "$AUDIO")
    done

    CMD+=(-map 0:v:0)

    if [[ "$MODE" == "add" ]]; then
        local EXISTING_AUDIO_COUNT
        EXISTING_AUDIO_COUNT=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$VIDEO" | wc -l)
        for ((i=0; i<EXISTING_AUDIO_COUNT; i++)); do
            CMD+=(-map 0:a:$i)
        done
    fi

    local AUDIO_INPUT_START=1
    for ((i=0; i<${#AUDIO_FILES[@]}; i++)); do
        CMD+=(-map "$((AUDIO_INPUT_START+i)):a:0")
    done

    CMD+=(-c:v copy)

    if [[ "$MODE" == "add" ]]; then
        for ((i=0; i<EXISTING_AUDIO_COUNT; i++)); do
            CMD+=(-c:a:$i copy)
        done
    fi

    for ((i=0; i<${#AUDIO_FILES[@]}; i++)); do
        local index=$((i + (MODE == "add" ? EXISTING_AUDIO_COUNT : 0)))
        CMD+=(-c:a:$index "$CODEC")
        [[ "$CODEC" != "wav" ]] && CMD+=(-b:a:$index "$USER_BITRATE")
        CMD+=(-metadata:s:a:$index title="${TITLES[$i]}")
    done

    local OUTFILE_SUFFIX="_with_AD"
    [[ "$MODE" == "replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
    local OUTFILE="${OUTDIR}/${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"
    CMD+=("$OUTFILE")

    echo
    echo "🚀 Muxing command:"
    echo "${CMD[@]}"
    echo
    "${CMD[@]}"
}

# === Main Logic ===

if [[ "$AUDIO_ONLY" == true ]]; then
    is_file "$INPUT1" || { echo "❌ You must provide an audio file."; exit 1; }
    prompt_settings
    process_audio_only "$INPUT1" "$(dirname "$INPUT1")"
    echo
    echo "✅ Audio-only re-encode complete."
    exit 0
fi

if is_file "$INPUT1" && is_file "${INPUTS[0]}"; then
    MODE_TYPE="single"
elif is_directory "$INPUT1" && is_directory "${INPUTS[0]}"; then
    MODE_TYPE="batch"
else
    echo "❌ Invalid input types."
    print_usage
fi

if [[ "$MODE_TYPE" == "single" ]]; then
    prompt_settings
    process_pair "$INPUT1" "${INPUTS[@]}"
    echo
    echo "✅ Single mux complete."
    exit 0
fi

# Batch mode
VIDEO_FILES=()
AUDIO_FILES=()
while IFS= read -r -d '' file; do VIDEO_FILES+=("$file"); done < <(find "$INPUT1" -type f -print0 | sort -z)
while IFS= read -r -d '' file; do AUDIO_FILES+=("$file"); done < <(find "${INPUTS[0]}" -type f -print0 | sort -z)

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
    process_pair "${VIDEO_FILES[$i]}" "${AUDIO_FILES[$i]}"
done

echo
echo "✅ Batch complete."
