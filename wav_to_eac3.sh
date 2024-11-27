#!/bin/bash

# Script to convert a .wav file to .eac3 with explicit dialogue normalization.

# Check for input
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <input_wav_file>"
    exit 1
fi

# Input .wav file
input_wav="$1"

# Output .eac3 file
output_eac3="${input_wav%.*}.eac3"

# Prompt for metadata
echo "Enter dialogue normalization value (default: -24):"
read dialnorm_value
dialnorm_value=${dialnorm_value:--24}

echo "Enter track title (e.g., 'English - Audio Description E-AC3'):"
read track_title
track_title=${track_title:-"English - Audio Description E-AC3"}

echo "Enter track language (default: eng):"
read track_language
track_language=${track_language:-eng}

# Encode to E-AC3 with explicit dialnorm and metadata
ffmpeg -i "$input_wav" -c:a eac3 -b:a 224k -dialnorm "$dialnorm_value" \
    -metadata service_type="VI" \
    -metadata title="$track_title" \
    -metadata language="$track_language" \
    "$output_eac3"

# Check for success
if [ $? -eq 0 ]; then
    echo "Conversion completed successfully. Output file: $output_eac3"
else
    echo "Conversion failed."
    exit 1
fi
