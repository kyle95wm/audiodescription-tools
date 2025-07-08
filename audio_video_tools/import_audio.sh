#!/usr/bin/env bash

# === Auto-updater ===
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

cleanup_temp() {
    if [[ "$1" == "$2" ]]; then
        echo "ℹ️ Skipping cleanup: same as original input."
    elif [[ -f "$1" ]]; then
        rm "$1"
    fi
}

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
    else
        echo "[ℹ️] No config file found."
    fi
else
    echo "[⚠️] Config file loading disabled."
fi

get_default_flag() {
    [[ "$MODE" == "add" && "$SET_AD_DEFAULT" =~ ^[Yy]$ ]] && echo "-disposition:a:1 default"
}

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

    if [[ "$MODE" == "add" ]]; then
        read -p "Set AD as default audio? (Y/N) [default=${SET_AD_DEFAULT:-N}]: " d
        SET_AD_DEFAULT="${d:-$SET_AD_DEFAULT}"
        DEFAULT_FLAG=$(get_default_flag)
    fi

    echo
    read -p "Copy subtitle tracks from original video? (Y/N) [default=${COPY_SUBTITLES:-Y}]: " cs
    COPY_SUBTITLES="${cs:-$COPY_SUBTITLES}"
}

prompt_settings() {
    prompt_codec_and_bitrate
    [[ "$AUDIO_ONLY" == false ]] && prompt_muxing_settings
}

process_pair() {
    local VIDEO="$1"
    local AUDIO="$2"
    local OUTDIR="$3"
    local BASENAME=$(basename "${VIDEO%.*}")
    local EXTENSION="${VIDEO##*.}"
    local OUTFILE_SUFFIX="_with_AD"
    [[ "$MODE" == "replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
    local OUTFILE="${OUTDIR}/${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"

    local CLEAN_INPUT="${OUTDIR}/${BASENAME}_cleaned_input.${CONTAINER}"
    local SUBS_TEMP_DIR
    SUBS_TEMP_DIR=$(mktemp -d)

    declare -a SUB_MAPS
    declare -a SUB_ARGS
    declare -a SUB_METADATA

    if [[ "$COPY_SUBTITLES" =~ ^[Yy]$ ]]; then
        local sub_index=0
        while IFS= read -r codec; do
            local sub_file="${SUBS_TEMP_DIR}/sub${sub_index}.srt"

            if [[ "$EXTENSION" == "mp4" && "$codec" == "mov_text" && "$CONTAINER" == "mkv" ]]; then
                ffmpeg -y -i "$VIDEO" -map 0:s:$sub_index "$sub_file" >/dev/null 2>&1
                if [[ -f "$sub_file" ]]; then
                    SUB_ARGS+=("-sub_charenc" "UTF-8" "-i" "$sub_file")
                    SUB_METADATA+=("-metadata:s:s:$sub_index" "language=eng")
                fi
            elif [[ "$CONTAINER" == "mp4" && "$codec" == "mov_text" ]]; then
                SUB_MAPS+=("-map 0:s:$sub_index")
                SUB_ARGS+=("-c:s:$sub_index" mov_text)
                SUB_METADATA+=("-metadata:s:s:$sub_index" "language=eng")
            elif [[ "$CONTAINER" == "mkv" ]]; then
                ffmpeg -y -i "$VIDEO" -map 0:s:$sub_index "$sub_file" >/dev/null 2>&1
                if [[ -f "$sub_file" ]]; then
                    SUB_ARGS+=("-sub_charenc" "UTF-8" "-i" "$sub_file")
                    SUB_METADATA+=("-metadata:s:s:$sub_index" "language=eng")
                fi
            else
                echo "⚠️ Skipping unsupported subtitle stream $sub_index ($codec)"
            fi
            ((sub_index++))
        done < <(ffprobe -v error -select_streams s -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "$VIDEO")
    fi

    if [[ "$EXTENSION" == "mp4" && "$CONTAINER" == "mp4" ]]; then
        ffmpeg -y -i "$VIDEO" -map 0:v -map 0:a -c copy "$CLEAN_INPUT" >/dev/null 2>&1 || {
            echo "❌ Failed to clean MP4 input."; return 1;
        }
    else
        CLEAN_INPUT="$VIDEO"
    fi

    CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=nokey=1:noprint_wrappers=1 "$AUDIO")
    [[ -z "$CHANNELS" ]] && CHANNELS=2
    [[ -z "$USER_BITRATE" && "$CODEC" != "wav" ]] && USER_BITRATE=$([[ "$CHANNELS" -ge 6 ]] && echo "640k" || echo "224k")

    echo
    echo "🎬 $(basename "$VIDEO") ⇄ $(basename "$AUDIO") → $OUTFILE"

    if [[ "$MODE" == "add" ]]; then
        ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" "${SUB_ARGS[@]}" \
            -map 0:v:0 -map 0:a:0 -map 1:a:0 "${SUB_MAPS[@]}" \
            -c:v copy -c:a copy -c:a:1 "$CODEC" -b:a:1 "$USER_BITRATE" \
            ${DEFAULT_FLAG:+-disposition:a:1 default} "${SUB_METADATA[@]}" "$OUTFILE"
    else
        ffmpeg -y -i "$CLEAN_INPUT" -i "$AUDIO" "${SUB_ARGS[@]}" \
            -map 0:v:0 -map 1:a:0 "${SUB_MAPS[@]}" \
            -c:v copy -c:a "$CODEC" -b:a "$USER_BITRATE" "${SUB_METADATA[@]}" "$OUTFILE"
    fi

    cleanup_temp "$CLEAN_INPUT" "$VIDEO"
    [[ -d "$SUBS_TEMP_DIR" ]] && rm -rf "$SUBS_TEMP_DIR"
}

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
while IFS= read -r -d '' file; do VIDEO_FILES+=("$file"); done < <(find "$INPUT1" -type f -print0 | sort -zV)
while IFS= read -r -d '' file; do AUDIO_FILES+=("$file"); done < <(find "$INPUT2" -type f -print0 | sort -zV)

NUM_VID=${#VIDEO_FILES[@]}
NUM_AUD=${#AUDIO_FILES[@]}
PAIRS=$((NUM_VID<NUM_AUD ? NUM_VID : NUM_AUD))

echo
echo "🧾 Pairing:"
for ((i=0; i<PAIRS; i++)); do
    echo "  [$((i+1))] $(basename "${VIDEO_FILES[$i]}") ⇄ $(basename "${AUDIO_FILES[$i]}")"
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
