#!/bin/bash

# Script to mux a stereo AD track into a video file, optionally encode to E-AC3, and handle default audio track settings.

# Function to auto-detect files based on common patterns
auto_detect_files() {
    local video_exts=("mp4" "mkv" "avi")
    local stereo_suffix="_Stereo.wav"

    for ext in "${video_exts[@]}"; do
        video_file=$(ls *.$ext 2> /dev/null | head -n 1)
        if [[ -n "$video_file" ]]; then
            break
        fi
    done

    stereo_audio_file=$(ls *$stereo_suffix 2> /dev/null | head -n 1)
}

# Check if the minimum number of arguments is provided
if [ "$#" -eq 0 ]; then
    echo "No arguments provided. Auto-detecting files..."
    auto_detect_files
    if [[ -z "$video_file" || -z "$stereo_audio_file" ]]; then
        echo "Could not auto-detect all required files. Exiting."
        exit 1
    fi
elif [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_video> <stereo_ad_audio>"
    exit 1
else
    video_file="$1"
    stereo_audio_file="$2"
fi

# Ask if the user wants to encode the stereo track to E-AC3
echo "Do you want to encode the stereo AD track to E-AC3? (y/n, default: y)"
read encode_to_eac3
encode_to_eac3=${encode_to_eac3:-y}

# If encoding to E-AC3, ask for dialogue normalization level
if [[ "$encode_to_eac3" == "y" || "$encode_to_eac3" == "Y" ]]; then
    echo "Enter the dialogue normalization level for E-AC3:"
    echo " - Recommended value: -24 (standard for broadcast and streaming)"
    echo " - Format: A whole number between -1 and -31 (default: -24)"
    echo " - Example: Enter -24 for typical use or -27 for slightly quieter dialogue."
    read dialnorm_value

    # Validate input or use default if invalid
    if [[ ! "$dialnorm_value" =~ ^-([1-9]|[12][0-9]|3[01])$ ]]; then
        echo "Invalid input. Using default value of -24."
        dialnorm_value="-24"
    fi

    # Encode stereo track to E-AC3
    eac3_audio_file="${stereo_audio_file%.*}_eac3.wav"
    echo "Encoding stereo track to E-AC3 with dialnorm: $dialnorm_value"
    ffmpeg -i "$stereo_audio_file" \
        -c:a eac3 -b:a 224k -dialnorm "$dialnorm_value" \
        "$eac3_audio_file"
    stereo_audio_file="$eac3_audio_file"
fi

# Ask if the user wants to remove the original audio
echo "Do you want to remove the original audio from the video? (y/n, default: y)"
read remove_audio_answer
remove_audio_answer=${remove_audio_answer:-y}
remove_original_audio=0
if [[ "$remove_audio_answer" == "y" || "$remove_audio_answer" == "Y" ]]; then
    remove_original_audio=1
else
    # Ask if the AD track should be the default track
    echo "Do you want to make the AD track the default audio track? (y/n, default: n)"
    read make_ad_default
    make_ad_default=${make_ad_default:-n}
fi

# Ask for the output file name
echo "What would you like to call the output file (excluding extension)? Leave blank for default naming."
read output_filename_base
if [ -z "$output_filename_base" ]; then
    output_filename_base="ad_${video_file%.*}_with_AD"
fi
output_video="${output_filename_base}.mp4"

# Construct the ffmpeg command
ffmpeg_cmd="ffmpeg -i \"$video_file\" -i \"$stereo_audio_file\" -map 0:v -c:v copy"

if [ "$remove_original_audio" -eq 1 ]; then
    ffmpeg_cmd+=" -map 1:a -metadata:s:a:0 language=eng -metadata:s:a:0 title=\"English - Audio Description Stereo\""
else
    ffmpeg_cmd+=" -map 0:a -map 1:a"

    # If AD track should be default
    if [[ "$make_ad_default" == "y" || "$make_ad_default" == "Y" ]]; then
        ffmpeg_cmd+=" -disposition:a:1 default -metadata:s:a:1 language=eng -metadata:s:a:1 title=\"English - Audio Description Stereo\""
    else
        ffmpeg_cmd+=" -disposition:a:0 default -metadata:s:a:1 language=eng -metadata:s:a:1 title=\"English - Audio Description Stereo\""
    fi
fi

ffmpeg_cmd+=" \"$output_video\""

# Execute the command
echo "Executing command:"
echo $ffmpeg_cmd
eval $ffmpeg_cmd
