#!/usr/bin/env python3

import os
import sys
import subprocess

def burn_subtitles(video_file, srt_file):
    # Ensure the provided video and SRT files exist
    if not os.path.isfile(video_file):
        print(f"Error: The video file '{video_file}' does not exist.")
        return
    if not os.path.isfile(srt_file):
        print(f"Error: The subtitle file '{srt_file}' does not exist.")
        return

    # Construct the output file name
    video_dir, video_name = os.path.split(video_file)
    output_file = os.path.join(video_dir, f"burn_{video_name}")

    # Construct the FFmpeg command
    ffmpeg_command = [
        'ffmpeg',
        '-i', video_file,
        '-vf', f"subtitles={srt_file}",
        '-c:a', 'copy',
        output_file
    ]

    # Run the FFmpeg command
    try:
        subprocess.run(ffmpeg_command, check=True)
        print(f"Subtitles burned into video successfully. Output file: '{output_file}'")
    except subprocess.CalledProcessError as e:
        print(f"Error: FFmpeg failed with exit code {e.returncode}")
        print(e.output)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python burn_subtitles.py <video_file> <srt_file>")
    else:
        video_file = sys.argv[1]
        srt_file = sys.argv[2]
        burn_subtitles(video_file, srt_file)
