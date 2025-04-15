#!/bin/bash

print_usage() {
    echo "Usage: $0 <video_file> <audio_file>"
    echo
    echo "This script adds or replaces audio tracks in a video file."
    echo "You'll be prompted to choose between adding or replacing the audio."
    exit 1
}

# === Check dependencies ===
command -v ffmpeg >/dev/null 2>&1 || { echo "❌ ffmpeg is not installed."; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "❌ ffprobe is not installed."; exit 1; }

file_exists() {
    if [ ! -f "$1" ]; then
        echo "❌ File not found: $1"
        exit 1
    fi
}

# === Parse arguments ===
VIDEO="$1"
AUDIO="$2"

[ -z "$VIDEO" ] && print_usage
[ -z "$AUDIO" ] && print_usage

file_exists "$VIDEO"
file_exists "$AUDIO"

BASENAME=$(basename "$VIDEO")
BASENAME="${BASENAME%.*}"

# === Prompt for mode (add or replace) ===
echo
echo "What would you like to do with the new audio file?"
echo "  1) Add it as a second audio track (original audio stays)"
echo "  2) Replace all existing audio with it"
read -p "Enter your choice [1–2, default=1]: " MODE_CHOICE
MODE_CHOICE="${MODE_CHOICE:-1}"

case "$MODE_CHOICE" in
    1) MODE="--add" ;;
    2) MODE="--replace" ;;
    *) echo "❌ Invalid choice. Please enter 1 or 2."; exit 1 ;;
esac

# === Detect channel count ===
CHANNELS=$(ffprobe -v error -select_streams a:0 -show_entries stream=channels \
    -of default=nokey=1:noprint_wrappers=1 "$AUDIO")

if [[ "$CHANNELS" -eq 6 ]]; then
    CHANNEL_DESC="5.1 surround"
elif [[ "$CHANNELS" -eq 2 ]]; then
    CHANNEL_DESC="stereo"
elif [[ "$CHANNELS" -eq 1 ]]; then
    CHANNEL_DESC="mono"
else
    CHANNEL_DESC="$CHANNELS-channel"
fi

echo
echo "[Info] Detected $CHANNEL_DESC audio in input file."

# === Suggest audio format based on channels ===
echo
echo "Choose output audio format:"
if [[ "$CHANNELS" -eq 6 ]]; then
    echo "  1) EAC-3 (Dolby Digital Plus 5.1) [recommended]"
    echo "  2) WAV (uncompressed 5.1 PCM)"
    read -p "Enter your choice [1–2, default=1]: " FORMAT_CHOICE
    FORMAT_CHOICE="${FORMAT_CHOICE:-1}"

    case "$FORMAT_CHOICE" in
        1) CODEC="eac3"; EXT="eac3" ;;
        2) CODEC="pcm_s24le"; EXT="wav" ;;
        *) echo "❌ Invalid choice."; exit 1 ;;
    esac

else
    echo "  1) WAV (uncompressed 24-bit PCM) [default]"
    echo "  2) AAC (compressed stereo)"
    echo "  3) EAC-3 (Dolby Digital Plus stereo)"
    read -p "Enter your choice [1–3, default=1]: " FORMAT_CHOICE
    FORMAT_CHOICE="${FORMAT_CHOICE:-1}"

    case "$FORMAT_CHOICE" in
        1) CODEC="pcm_s24le"; EXT="wav" ;;
        2) CODEC="aac"; EXT="aac" ;;
        3) CODEC="eac3"; EXT="eac3" ;;
        *) echo "❌ Invalid choice."; exit 1 ;;
    esac
fi

# === Choose container format ===
echo
echo "Choose container format:"
echo "  1) MP4 (good compatibility — use with AAC only) [default]"
echo "  2) MKV (preferred for WAV or EAC-3)"
read -p "Enter your choice [1–2, default=1]: " CONTAINER_CHOICE
CONTAINER_CHOICE="${CONTAINER_CHOICE:-1}"

# Default to user’s selection first
case "$CONTAINER_CHOICE" in
    1) CONTAINER="mp4" ;;
    2) CONTAINER="mkv" ;;
    *) echo "❌ Invalid choice. Please enter 1 or 2."; exit 1 ;;
esac

# Override MP4 if using PCM or EAC-3
if [[ "$CONTAINER" == "mp4" && ("$CODEC" == "pcm_s24le" || "$CODEC" == "eac3") ]]; then
    echo
    echo "⚠️  MP4 does not reliably support WAV or EAC-3 audio."
    echo "👉 Switching to MKV for maximum compatibility."
    CONTAINER="mkv"
fi

# === Set default audio track (only applies to --add) ===
DEFAULT_FLAG=""
if [[ "$MODE" == "--add" ]]; then
    echo
    read -p "Set AD narration as the default audio track? [y/N]: " DEFAULT_CHOICE
    [[ "$DEFAULT_CHOICE" =~ ^[Yy]$ ]] && DEFAULT_FLAG="-disposition:a:1 default"
fi

# === Output file name ===
OUTFILE_SUFFIX="_with_AD"
[[ "$MODE" == "--replace" ]] && OUTFILE_SUFFIX="_replaced_audio"
OUTFILE="${BASENAME}${OUTFILE_SUFFIX}.${CONTAINER}"

# === Run FFmpeg ===
echo
if [[ "$MODE" == "--add" ]]; then
    echo ">> Adding AD narration as a second audio track..."
    ffmpeg -y -i "$VIDEO" -i "$AUDIO" \
        -map 0:v -map 0:a -map 1:a \
        -c:v copy -c:a copy -c:a:2 "$CODEC" \
        -ac:a:2 "$CHANNELS" \
        $DEFAULT_FLAG \
        -metadata:s:a:1 title="Original Audio" \
        -metadata:s:a:2 title="Audio Description - English" \
        -metadata:s:a:2 language=eng \
        "$OUTFILE"

elif [[ "$MODE" == "--replace" ]]; then
    echo ">> Replacing all audio tracks with AD narration..."
    ffmpeg -y -i "$VIDEO" -i "$AUDIO" \
        -map 0:v -map 1:a \
        -c:v copy -c:a "$CODEC" \
        -ac "$CHANNELS" \
        -metadata:s:a:0 title="Audio Description - English" \
        -metadata:s:a:0 language=eng \
        "$OUTFILE"

else
    echo "❌ Invalid mode: $MODE"
    exit 1
fi

echo
echo "✅ Done! Output file created:"
echo "   $OUTFILE"
