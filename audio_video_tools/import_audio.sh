#!/usr/bin/env bash

# === Auto-updater ===
UPDATE_URL="https://raw.githubusercontent.com/kyle95wm/audiodescription-tools/main/audio_video_tools/import_audio.sh?$(date +%s)"
SCRIPT_PATH="$(realpath "$0")"

if [[ "$1" != "--no-update" ]]; then
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
else
    echo "[⏭️] Skipping auto-update (debug mode)."
    shift
fi

# Ensure required tools are present
command -v ffmpeg >/dev/null || { echo "❌ ffmpeg not found."; exit 1; }
command -v ffprobe >/dev/null || { echo "❌ ffprobe not found."; exit 1; }
command -v mkvmerge >/dev/null || { echo "❌ mkvmerge not found."; exit 1; }

VIDEO="$1"
AUDIO="$2"

[[ ! -f "$VIDEO" || ! -f "$AUDIO" ]] && { echo "Usage: $0 <video_file> <audio_file> [--no-update]"; exit 1; }

OUTFILE="${VIDEO%.*}_replaced_audio.mkv"
TMPDIR=$(mktemp -d)
CLEAN_AUDIO="$TMPDIR/clean.wav"
ENCODED_AUDIO="$TMPDIR/converted.eac3"
SUBFILE="$TMPDIR/subs.srt"

# Step 1: Convert audio to EAC3
echo "[🎧] Converting audio to eac3..."
ffmpeg -y -i "$AUDIO" -ar 48000 -c:a eac3 -b:a 224k "$ENCODED_AUDIO"

# Step 2: Strip audio markers (optional here, just copy-cleaning)
ffmpeg -y -i "$AUDIO" -map 0:a:0 -c:a copy "$CLEAN_AUDIO"

# Step 3: Extract subtitles if present
echo "[📜] Extracting subtitles..."
SUBIDX=$(ffprobe -loglevel error -select_streams s -show_entries stream=index -of csv=p=0 "$VIDEO" | head -n 1)
if [[ -n "$SUBIDX" ]]; then
    ffmpeg -y -i "$VIDEO" -map 0:s:$SUBIDX "$SUBFILE"
    HAS_SUBS=true
else
    echo "[ℹ️] No subtitle stream found. Skipping."
    HAS_SUBS=false
fi

# Step 4: Mux video + new audio (+ subs if present)
echo "[🎞️] Muxing final file..."
if [[ "$HAS_SUBS" == true ]]; then
    mkvmerge -o "$OUTFILE" -D "$VIDEO" "$ENCODED_AUDIO" --language 0:eng "$SUBFILE"
else
    mkvmerge -o "$OUTFILE" -D "$VIDEO" "$ENCODED_AUDIO"
fi

# Step 5: Cleanup
echo "[🧹] Cleaning up..."
rm -rf "$TMPDIR"
echo "[✅] Done: $OUTFILE"
