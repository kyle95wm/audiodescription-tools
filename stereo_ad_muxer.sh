#!/bin/bash

# Script to encode a stereo AD track to E-AC3, mux it with a video file, and set it as default.

# Check for required inputs
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <input_video> <stereo_ad_audio> [output_video]"
    exit 1
fi

# Input files
video_file="$1"
stereo_audio_file="$2"
eac3_audio_file="${stereo_audio_file%.*}_eac3.eac3"

# Output file
if [ -z "$3" ]; then
    output_video="${video_file%.*}_with_AD.mp4"
else
    output_video="$3"
fi

# Check if input files exist
if [ ! -f "$video_file" ]; then
    echo "Error: Video file '$video_file' not found."
    exit 1
fi

if [ ! -f "$stereo_audio_file" ]; then
    echo "Error: Stereo AD audio file '$stereo_audio_file' not found."
    exit 1
fi

# Encode the stereo track to E-AC3
echo "Encoding stereo track to E-AC3..."
ffmpeg -i "$stereo_audio_file" -c:a eac3 -b:a 224k -dialnorm -24 "$eac3_audio_file"
if [[ -f "$eac3_audio_file" ]]; then
    echo "E-AC3 encoding successful: $eac3_audio_file"
else
    echo "E-AC3 encoding failed. Exiting."
    exit 1
fi

# Ask if the AD track should be the default track
echo "Do you want to make the AD track the default audio track? (y/n, default: y)"
read make_ad_default
make_ad_default=${make_ad_default:-y}

# Construct the ffmpeg command for muxing
ffmpeg_cmd="ffmpeg -i \"$video_file\" -i \"$eac3_audio_file\" -map 0:v -c:v copy"

# Add the AD track as the first audio stream (force copy of E-AC3)
ffmpeg_cmd+=" -map 1:a -c:a:0 copy -metadata:s:a:0 language=eng -metadata:s:a:0 title=\"English - Audio Description E-AC3\""

# Add the original audio track as the second audio stream
ffmpeg_cmd+=" -map 0:a -c:a:1 copy -metadata:s:a:1 language=eng -metadata:s:a:1 title=\"English - Original Audio\""

# Handle default audio track disposition
if [[ "$make_ad_default" =~ ^[yY]$ ]]; then
    ffmpeg_cmd+=" -disposition:a:0 default -disposition:a:1 none"
else
    ffmpeg_cmd+=" -disposition:a:1 default -disposition:a:0 none"
fi

ffmpeg_cmd+=" \"$output_video\""

# Execute the command
echo "Executing command:"
echo $ffmpeg_cmd
eval $ffmpeg_cmd

# Verify the output
if [[ -f "$output_video" ]]; then
    echo "Muxing completed successfully: $output_video"

    # Cleanup intermediate files
    echo "Cleaning up intermediate files..."
    rm -f "$eac3_audio_file"
    echo "Removed: $eac3_audio_file"
else
    echo "Muxing failed. Exiting."
    exit 1
fi
