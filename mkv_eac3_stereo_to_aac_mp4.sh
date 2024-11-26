#!/bin/bash

# Script to convert video files with E-AC3 stereo tracks to MP4 with AAC stereo tracks.

# Check for required inputs
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <input_video> [output_video]"
    exit 1
fi

# Input file
input_file="$1"

# Output file
if [ -z "$2" ]; then
    output_file="${input_file%.*}_aac.mp4"
else
    output_file="$2"
fi

# Check if the input file exists
if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' not found."
    exit 1
fi

# Display available streams for debugging
echo "Available streams in '$input_file':"
ffprobe -v error -show_entries stream=index,codec_name,channels -select_streams a -of csv=p=0 "$input_file"

# Convert the E-AC3 audio stream to AAC
ffmpeg -i "$input_file" -map 0:v -c:v copy \
-map 0:1 -c:a aac -b:a 128k \
"$output_file" -y

# Check if the conversion was successful
if [ $? -eq 0 ]; then
    echo "Conversion completed successfully. Output file: $output_file"
else
    echo "Conversion failed."
    exit 1
fi