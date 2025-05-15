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
    echo "  Single mux: $0 <video_file> <audio_file>"
    echo "  Batch mux:  $0 <video_folder> <audio_folder> [output_folder]"
    echo "  Audio only: $0 <audio_file> --audio-only"
    echo
    echo "Optional flags:"
    echo "  --no-config | -nc      Ignore saved config file"
    echo "  --audio-only | -ao     Re-encode only the audio"
    exit 1
}

command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found."; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found."; exit 1; }

[[ $# -lt 1 ]] && print_usage

INPUT1="$1"
INPUT2="$2"
OUTPUT_DIR="${3:-$(pwd)}"

NO_CONFIG=false
AUDIO_ONLY=false
for arg in "$@"; do
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
        DEFAULT_CONTAINER="${CONTAINER:-mkv}"
        read -p "Select container (mp4/mkv) [default=$DEFAULT_CONTAINER]: " cont
        CONTAINER="${cont:-$DEFAULT_CONTAINER}"
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

    if [[ -z "$USER_BITRATE" && "$CODEC" != "wav" ]]; then
        if [[ "$CHANNELS" == "2" ]]; then
            USER_BITRATE="224k"
            echo "[ℹ️] Defaulting to 224k for EAC3 stereo."
        elif [[ "$CHANNELS" -ge 6 ]]; then
            USER_BITRATE="640k"
            echo "[ℹ️] Defaulting to 640k for EAC3 5.1+ surround."
        else
            USER_BITRATE="224k"
            echo "[ℹ️] Defaulting to 224k fallback."
        fi
    fi

    if [[ "$CODEC" == "wav" ]]; then
        ffmpeg -y -i "$AUDIO" -c:a "$CODEC" -ac "$CHANNELS" "$OUTFILE"
    else
        ffmpeg -y -i "$AUDIO" -c:a "$CODEC" -b:a "$USER_BITRATE" -ac "$CHANNELS" "$OUTFILE"
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
    local EXTENSION="${VIDEO##*.}"

    if [[ "$EXTENSION" == "mp4" ]]; then
        CLEAN_INPUT="${OUTDIR}/${BASENAME}_cleaned_input.${CONTAINER}"
        ffmpeg -y -i "$VIDEO" -map 0:v -map 0:a -map 0:s\? -c copy "$CLEAN_INPUT" || {
            echo "❌ Failed to clean MP4 input. Aborting."
            return 1
        }
    else
        CLEAN_INPUT="$VIDEO"
    fi

    CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels \
        -of default=nokey=1:noprint_wrappers=1 "$AUDIO")
    [[ -z "$CHANNELS" ]] && CHANNELS=2

    if [[ -z "$USER_BITRATE" && "$CODEC" != "wav" ]]; then
        if [[ "$CHANNELS" == "2" ]]; then
            USER_BITRATE="224k"
        elif [[ "$CHANNELS" -ge 6 ]]; then
            USER_BITRATE="640k"
        else
            USER_BITRATE="224k"
        fi
    fi

    local OUTFILE_SUFFIX="_with_AD"
    [[ "$MODE" == "replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
    local OUTFILE="${OUTDIR}/${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"

    echo
    echo "🎬 $(basename "$VIDEO") ⇄ $(basename "$AUDIO") → $OUTFILE"

    if [[ "$MODE" == "add" ]]; then
        ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" \
            -map 0:v:0 -map 0:a:0 -map 1:a:0 \
            -c:v copy -c:a copy -c:a:1 "$CODEC" -b:a:1 "$USER_BITRATE" \
            $DEFAULT_FLAG "$OUTFILE"
    else
        ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" \
            -map 0:v:0 -map 1:a:0 \
            -c:v copy -c:a "$CODEC" -b:a "$USER_BITRATE" \
            "$OUTFILE"
    fi

    cleanup_temp "$CLEAN_INPUT" "$VIDEO"
}

# === Main Run ===
if [[ "$AUDIO_ONLY" == true ]]; then
    is_file "$INPUT1" || { echo "❌ You must provide an audio file."; exit 1; }
    prompt_settings
    process_audio_only "$INPUT1" "$(dirname "$INPUT1")"
    echo
    echo "✅ Audio-only re-encode complete."
    exit 0
fi

if is_file "$INPUT1" && is_file "$INPUT2"; then
    MODE_TYPE="single"
elif is_directory "$INPUT1" && is_directory "$INPUT2"; then
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
