#!/bin/bash

# Function to auto-detect files based on common patterns
auto_detect_files() {
    echo "🔍 Auto-detect mode: looking for the following..."
    echo "- A video file (.mp4, .mkv, .avi)"
    echo "- An optional stereo audio file with '_Stereo.wav' suffix"
    echo "- An optional 5.1 audio file with '_SixChannel.wav' suffix"

    local video_exts=("mp4" "mkv" "avi")
    for ext in "${video_exts[@]}"; do
        video_file=$(ls *."$ext" 2>/dev/null | head -n 1)
        if [[ -n "$video_file" ]]; then
            echo "✅ Found video file: $video_file"
            break
        fi
    done

    if [[ -n "$video_file" ]]; then
        base_name="${video_file%.*}"
        stereo_audio_file="${base_name}_Stereo.wav"
        six_channel_audio_file="${base_name}_SixChannel.wav"

        if [[ -f "$stereo_audio_file" ]]; then
            echo "✅ Found stereo audio file: $stereo_audio_file"
        else
            stereo_audio_file=""
        fi

        if [[ -f "$six_channel_audio_file" ]]; then
            echo "✅ Found 5.1 audio file: $six_channel_audio_file"
        else
            six_channel_audio_file=""
        fi
    fi
}

# Argument parsing
dry_run=0
batch_mode=0
args=()

for arg in "$@"; do
    case "$arg" in
        --dry-run) dry_run=1 ;;
        --batch) batch_mode=1 ;;
        *) args+=("$arg") ;;
    esac
done

run_mux() {
    local video_file="$1"
    local stereo_audio_file="$2"
    local six_channel_audio_file="$3"

    echo "Do you want to remove the original audio from the video? (y/n, default: y) "
    read remove_audio_answer
    remove_audio_answer=${remove_audio_answer:-y}
    remove_original_audio=0
    [[ "$remove_audio_answer" =~ ^[Yy]$ ]] && remove_original_audio=1

    local make_51_default=0
    if [[ -n "$six_channel_audio_file" ]]; then
        echo "Do you want to make the 5.1 audio stream the default? (y/n, default: n) "
        read make_51_default_answer
        make_51_default_answer=${make_51_default_answer:-n}
        [[ "$make_51_default_answer" =~ ^[Yy]$ ]] && make_51_default=1
    fi

    echo "Output file name (excluding extension)? Leave blank for default:"
    read output_filename_base
    [[ -z "$output_filename_base" ]] && output_filename_base="ad_${video_file%.*}_with_AD"
    output_video="${output_filename_base}.mp4"

    ffmpeg_cmd="ffmpeg -i \"$video_file\""
    map_index=0

    if [[ -n "$stereo_audio_file" ]]; then
        ffmpeg_cmd+=" -i \"$stereo_audio_file\""
        ((map_index++))
    fi
    if [[ -n "$six_channel_audio_file" ]]; then
        ffmpeg_cmd+=" -i \"$six_channel_audio_file\""
        ((map_index++))
    fi

    ffmpeg_cmd+=" -map 0:v -c:v copy"

    if [[ "$remove_original_audio" -eq 1 ]]; then
        num_audio_streams=0
    else
        num_audio_streams=$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$video_file" | wc -l)
    fi

    if [[ -n "$six_channel_audio_file" ]]; then
        ffmpeg_cmd+=" -map $map_index:a -c:a:$num_audio_streams eac3 -b:a:$num_audio_streams 640k -metadata:s:a:$num_audio_streams language=eng -metadata:s:a:$num_audio_streams title=\"English - Audio Description 5.1\""
        [[ "$make_51_default" -eq 1 ]] && ffmpeg_cmd+=" -disposition:a:$num_audio_streams default"
        ((num_audio_streams++))
    fi

    if [[ -n "$stereo_audio_file" ]]; then
        ffmpeg_cmd+=" -map $( [[ -n "$six_channel_audio_file" ]] && echo "$((map_index - 1))" || echo "$map_index" ):a"
        ffmpeg_cmd+=" -c:a:$num_audio_streams aac -b:a:$num_audio_streams 192k -metadata:s:a:$num_audio_streams language=eng -metadata:s:a:$num_audio_streams title=\"English - Audio Description Stereo\""
        [[ "$make_51_default" -eq 0 ]] && ffmpeg_cmd+=" -disposition:a:$num_audio_streams default"
    fi

    ffmpeg_cmd+=" \"$output_video\""

    echo ""
    echo "Executing command:"
    echo "$ffmpeg_cmd"

    [[ "$dry_run" -eq 0 ]] && eval $ffmpeg_cmd || echo "(Dry run — command not executed.)"
}

# Main logic
if [[ "$batch_mode" -eq 1 ]]; then
    for f in *.mp4 *.mkv *.avi; do
        [[ -f "$f" ]] || continue
        base="${f%.*}"
        s="${base}_Stereo.wav"
        x="${base}_SixChannel.wav"
        run_mux "$f" "$([[ -f "$s" ]] && echo "$s")" "$([[ -f "$x" ]] && echo "$x")"
    done
elif [[ "${#args[@]}" -eq 0 ]]; then
    echo "No arguments provided. Attempting auto-detect..."
    auto_detect_files
    if [[ -z "$video_file" ]]; then
        echo "❌ Error: No video file found in the current directory."
        exit 1
    fi
    run_mux "$video_file" "$stereo_audio_file" "$six_channel_audio_file"
else
    video_file="${args[0]}"
    stereo_audio_file="${args[1]}"
    six_channel_audio_file="${args[2]}"
    run_mux "$video_file" "$stereo_audio_file" "$six_channel_audio_file"
fi
