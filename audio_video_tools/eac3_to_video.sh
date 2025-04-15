#!/bin/bash

# Script to merge a .eac3 audio file into a video file with metadata.

# Check for inputs
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_video_file> <input_eac3_file>"
    exit 1
fi

# Input files
input_video="$1"
input_eac3="$2"

# Output file
output_video="${input_video%.*}_with_eac3.mp4"

# Prompt to make the E-AC3 track the default
echo "Do you want to make the E-AC3 track the default audio? (y/n, default: n)"
read make_default
make_default=${make_default:-n}

# Prompt for track metadata
echo "Enter track title for the E-AC3 track (e.g., 'English - Audio Description E-AC3'):"
read track_title
track_title=${track_title:-"English - Audio Description E-AC3"}

echo "Enter track language for the E-AC3 track (default: eng):"
read track_language
track_language=${track_language:-eng}

# Construct FFmpeg command
ffmpeg_cmd="ffmpeg -i \"$input_video\" -i \"$input_eac3\" -map 0:v -c:v copy"

# Add .eac3 track with metadata
if [ "$make_default" == "y" ]; then
    ffmpeg_cmd+=" -map 1:a -c:a copy -disposition:a:0 default"
else
    ffmpeg_cmd+=" -map 1:a -c:a copy"
fi

# Add metadata for the E-AC3 track
ffmpeg_cmd+=" -metadata:s:a:0 title=\"$track_title\" -metadata:s:a:0 language=\"$track_language\""

# Set output file
ffmpeg_cmd+=" \"$output_video\" -y"

# Execute the command
echo "Executing command:"
echo $ffmpeg_cmd
eval $ffmpeg_cmd

# Check for success
if [ $? -eq 0 ]; then
    echo "Merging completed successfully. Output file: $output_video"
else
    echo "Merging failed."
    exit 1
fi
