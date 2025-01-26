#!/usr/bin/env python3

import subprocess
import os
import sys

def extract_video_stream(input_file):
    """
    Extracts only the video stream from a given video file and saves it to a new file
    with the prefix 'vo_' in the filename.
    
    :param input_file: Path to the input video file.
    """
    # Check if the input file exists
    if not os.path.isfile(input_file):
        print(f"Error: Input file '{input_file}' does not exist.")
        return

    # Generate the output file name
    base_name = os.path.basename(input_file)  # Get the file name with extension
    file_name, ext = os.path.splitext(base_name)  # Split the name and extension
    output_file = f"vo_{file_name}{ext}"  # Add 'vo_' prefix to the name

    # FFmpeg command to copy only the video stream
    command = [
        "ffmpeg", "-i", input_file,
        "-map", "0:v:0",  # Map only the first video stream
        "-c:v", "copy",  # Copy the video codec without re-encoding
        "-an",  # Remove all audio streams
        output_file
    ]

    try:
        # Run the command
        subprocess.run(command, check=True)
        print(f"Video-only file saved as '{output_file}'.")
    except subprocess.CalledProcessError as e:
        print(f"Error: Failed to extract video stream. {e}")

if __name__ == "__main__":
    # Check if an argument was provided
    if len(sys.argv) != 2:
        print("Usage: python3 video_only.py <input_video_file>")
        sys.exit(1)

    # Get the input video file from the arguments
    input_video = sys.argv[1]
    extract_video_stream(input_video)
