#!/usr/bin/env bash

# === Auto-updater ===
# Automatically checks for and applies updates from the online repository
UPDATE_URL="https://raw.githubusercontent.com/kyle95wm/audiodescription-tools/main/audio_video_tools/import_audio.sh?$(date +%s)"
SCRIPT_PATH="$(realpath "$0")"

echo "[🔄] Checking for updates..."

LATEST_SCRIPT=$(mktemp) || { echo "❌ Failed to create temp file."; exit 1; }
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

# Displays script usage information
print_usage() {
    echo "Usage:"
    echo "  Single mux: $0 <video_file> <audio_file1> [audio_file2 ...]"
    echo "  Batch mux:  $0 <video_folder> <audio_folder> [output_folder]"
    echo "  Audio only: $0 <audio_file> --audio-only"
    echo
    echo "Optional flags:"
    echo "  --no-config | -nc      Ignore saved config file"
    echo "  --audio-only | -ao     Re-encode only the audio"
    exit 1
}

# Check required tools are installed
command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found."; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found."; exit 1; }

[[ $# -lt 1 ]] && print_usage

INPUT1="$1"
shift
AUDIO_FILES=()

# Parse arguments and flags
OUTPUT_DIR="$(pwd)"
NO_CONFIG=false
AUDIO_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --no-config|-nc) NO_CONFIG=true ;;
        --audio-only|-ao) AUDIO_ONLY=true ;;
        *) AUDIO_FILES+=("$arg") ;;
    esac
done

# Helper functions
is_directory() { [[ -d "$1" ]]; }
is_file() { [[ -f "$1" ]]; }

# Safely deletes temp files unless they are the original input
cleanup_temp() {
    if [[ "$1" == "$2" ]]; then
        echo "ℹ️ Skipping cleanup: same as original input."
    elif [[ -f "$1" ]]; then
        rm "$1"
    fi
}

# Load configuration file from known locations
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

# Determines whether to set the audio stream as default
get_default_flag() {
    [[ "$MODE" == "add" && "$SET_AD_DEFAULT" =~ ^[Yy]$ ]] && echo "-disposition:a:${DEFAULT_AUDIO_INDEX} default"
}

# Prompt user to select codec and optional bitrate
prompt_codec_and_bitrate() {
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
}

# Prompt for muxing options: container, mode, etc.
prompt_muxing_settings() {
    echo
    read -p "What would you like to do with the audio? (add/replace) [default=${MODE:-replace}]: " m
    MODE="${m:-$MODE}"

    echo
    DEFAULT_CONTAINER="${CONTAINER:-mkv}"
    read -p "Select container (mp4/mkv) [default=$DEFAULT_CONTAINER]: " cont
    CONTAINER="${cont:-$DEFAULT_CONTAINER}"
    [[ "$CONTAINER" == "mp4" && "$CODEC" != "aac" ]] && echo "⚠️ Forcing MKV due to codec" && CONTAINER="mkv"

    echo
    read -p "Strip marker chapters from audio? (Y/N) [default=${STRIP_MARKERS:-Y}]: " sm
    STRIP_MARKERS="${sm:-$STRIP_MARKERS}"

    if [[ "$MODE" == "add" && ${#AUDIO_FILES[@]} -gt 0 ]]; then
        read -p "Set AD as default audio? (Y/N) [default=${SET_AD_DEFAULT:-N}]: " d
        SET_AD_DEFAULT="${d:-$SET_AD_DEFAULT}"
    fi
}

# Combined prompting
prompt_settings() {
    prompt_codec_and_bitrate
    [[ "$AUDIO_ONLY" == false ]] && prompt_muxing_settings
}

# Mux video and one or more audio files into an output container
process_pair() {
    local VIDEO="$1"
    shift
    local AUDIO_LIST=("$@")
    local OUTDIR="$(dirname "$VIDEO")"
    local BASENAME=$(basename "${VIDEO%.*}")
    local EXTENSION="${VIDEO##*.}"

    CLEAN_INPUT="${OUTDIR}/${BASENAME}_cleaned_input.${CONTAINER}"

    # Clean MP4 subtitles depending on container
    if [[ "$EXTENSION" == "mp4" ]]; then
        if [[ "$CONTAINER" == "mp4" ]]; then
            ffmpeg -y -i "$VIDEO" -map 0:v -map 0:a -map 0:s\? -c copy "$CLEAN_INPUT" || {
                echo "❌ Failed to clean MP4 input (mp4 target). Aborting."
                return 1
            }
        else
            echo "[⚠️] Dropping MP4 subtitle stream (mov_text not supported in MKV)"
            ffmpeg -y -i "$VIDEO" -map 0:v -map 0:a -c copy "$CLEAN_INPUT" || {
                echo "❌ Failed to clean MP4 input (mkv target). Aborting."
                return 1
            }
        fi
    else
        CLEAN_INPUT="$VIDEO"
    fi

    # Build FFmpeg argument arrays
    local FF_ARGS=( -y -i "$CLEAN_INPUT" )
    local MAP_ARGS=( -map 0:v:0 )
    local AUDIO_INDEX=1

    for AUDIO_FILE in "${AUDIO_LIST[@]}"; do
        FF_ARGS+=( -i "$AUDIO_FILE" )
        MAP_ARGS+=( -map ${AUDIO_INDEX}:a:0 )
        AUDIO_INDEX=$((AUDIO_INDEX+1))
    done

    local OUTFILE_SUFFIX="_with_AD"
    [[ "$MODE" == "replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
    local OUTFILE="${OUTDIR}/${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"

    DEFAULT_AUDIO_INDEX=1
    DEFAULT_FLAG=$(get_default_flag)

    echo
    echo "🎬 $(basename "$VIDEO") ⇄ ${#AUDIO_LIST[@]} audio files → $OUTFILE"

    # Execute FFmpeg with stream mappings, encoding, and optional default flag
    ffmpeg "${FF_ARGS[@]}" "${MAP_ARGS[@]}" \
        -c:v copy $(for i in $(seq 1 ${#AUDIO_LIST[@]}); do echo -n "-c:a:$((i-1)) $CODEC -b:a:$((i-1)) $USER_BITRATE "; done) \
        $DEFAULT_FLAG "$OUTFILE"

    cleanup_temp "$CLEAN_INPUT" "$VIDEO"
}

# Handle audio-only re-encoding mode
if [[ "$AUDIO_ONLY" == true ]]; then
    is_file "$INPUT1" || { echo "❌ You must provide an audio file."; exit 1; }
    prompt_settings
    process_audio_only "$INPUT1" "$(dirname "$INPUT1")"
    echo
    echo "✅ Audio-only re-encode complete."
    exit 0
fi

# Determine operation mode based on input types
if is_file "$INPUT1" && [[ ${#AUDIO_FILES[@]} -gt 0 ]]; then
    MODE_TYPE="single"
elif is_directory "$INPUT1" && is_directory "${AUDIO_FILES[0]}"; then
    MODE_TYPE="batch"
else
    echo "❌ Invalid input types."
    print_usage
fi

# Run single-file mux operation
if [[ "$MODE_TYPE" == "single" ]]; then
    prompt_settings
    process_pair "$INPUT1" "${AUDIO_FILES[@]}"
    echo
    echo "✅ Single mux complete."
    exit 0
fi
