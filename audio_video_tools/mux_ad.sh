#!/bin/bash

# Auto-detect input video and audio files
auto_detect_files() {
    local video_exts=("mp4" "mkv" "avi")
    local stereo_suffix="_Stereo.wav"
    local six_channel_suffix="_SixChannel.wav"

    for ext in "${video_exts[@]}"; do
        video_file=$(ls *."$ext" 2>/dev/null | head -n 1)
        if [[ -n "$video_file" ]]; then
            break
        fi
    done

    if [[ -n "$video_file" ]]; then
        base="${video_file%.*}"
        stereo_audio_file="${base}${stereo_suffix}"
        six_channel_audio_file="${base}${six_channel_suffix}"

        [[ ! -f "$stereo_audio_file" ]] && stereo_audio_file=""
        [[ ! -f "$six_channel_audio_file" ]] && six_channel_audio_file=""
    fi
}

# Parse arguments
dry_run=0
for arg in "$@"; do
    [[ "$arg" == "--dry-run" ]] && dry_run=1
done

# Check if args are provided or fallback to auto-detect
if [ "$#" -eq 0 ] || [[ "$1" == "--dry-run" ]]; then
    echo "No arguments provided. Attempting to auto-detect files..."
    auto_detect_files

    if [[ -z "$video_file" ]]; then
        echo "❌ No video file found."
        exit 1
    fi
    if [[ -z "$stereo_audio_file" ]]; then
        echo "❌ Stereo AD file not found for '$video_file'."
        exit 1
    fi
else
    video_file="$1"
    stereo_audio_file="$2"
    six_channel_audio_file="${3:-}"

    base="${video_file%.*}"
    [[ ! -f "$stereo_audio_file" ]] && stereo_audio_file=""
    [[ ! -f "$six_channel_audio_file" ]] && six_channel_audio_file=""
fi

# Prompt user for audio handling options
read -p "Remove original audio? (y/n) [y]: " remove_audio
remove_audio=${remove_audio:-y}
remove_original_audio=0
[[ "$remove_audio" =~ ^[Yy]$ ]] && remove_original_audio=1

make_51_default=0
if [[ -n "$six_channel_audio_file" ]]; then
    read -p "Make 5.1 the default? (y/n) [n]: " make_default
    make_default=${make_default:-n}
    [[ "$make_default" =~ ^[Yy]$ ]] && make_51_default=1
fi

read -p "Output file name (no extension)? [default: ad_${base}_with_AD]: " out_name
out_name=${out_name:-"ad_${base}_with_AD"}
output_file="${out_name}.mkv"

# Start building ffmpeg command
ffmpeg_cmd="ffmpeg -i \"$video_file\" -i \"$stereo_audio_file\""
[[ -n "$six_channel_audio_file" ]] && ffmpeg_cmd+=" -i \"$six_channel_audio_file\""

ffmpeg_cmd+=" -map 0:v -c:v copy"

# Decide where to map audio tracks
if [ "$remove_original_audio" -eq 1 ]; then
    audio_index=0
else
    audio_index=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$video_file" | wc -l)
fi

# If 5.1 should be first
if [ "$make_51_default" -eq 1 ] && [[ -n "$six_channel_audio_file" ]]; then
    ffmpeg_cmd+=" -map 2:a -c:a:$audio_index eac3 -b:a:$audio_index 640k"
    ffmpeg_cmd+=" -metadata:s:a:$audio_index language=eng -metadata:s:a:$audio_index title=\"English - Audio Description 5.1\""
    let audio_index++
fi

# Always add stereo
ffmpeg_cmd+=" -map 1:a -c:a:$audio_index aac -b:a:$audio_index 192k"
ffmpeg_cmd+=" -metadata:s:a:$audio_index language=eng -metadata:s:a:$audio_index title=\"English - Audio Description Stereo\""
let audio_index++

# If 5.1 is added second
if [ "$make_51_default" -eq 0 ] && [[ -n "$six_channel_audio_file" ]]; then
    ffmpeg_cmd+=" -map 2:a -c:a:$audio_index eac3 -b:a:$audio_index 640k"
    ffmpeg_cmd+=" -metadata:s:a:$audio_index language=eng -metadata:s:a:$audio_index title=\"English - Audio Description 5.1\""
fi

ffmpeg_cmd+=" \"$output_file\""

# Output the result
echo ""
echo "✅ Command to be executed:"
echo "$ffmpeg_cmd"

if [[ "$dry_run" -eq 1 ]]; then
    echo "💤 Dry run mode enabled. No changes made."
    exit 0
fi

echo ""
echo "🚀 Running..."
eval $ffmpeg_cmd
