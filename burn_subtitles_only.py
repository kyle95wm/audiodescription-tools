#!/usr/bin/env python3

import os
import sys
import subprocess

def get_frame_rate(video_file):
    """Use FFmpeg to get the frame rate of the video."""
    result = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=r_frame_rate', '-of', 'default=noprint_wrappers=1:nokey=1', video_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    rate = result.stdout.decode().strip()
    num, denom = map(int, rate.split('/'))
    return num / denom

def burn_subtitles(video_file, srt_file, font_size=20):
    """Burn subtitles into the video with a default font size of 20."""
    if not os.path.isfile(video_file):
        print(f"Error: The video file '{video_file}' does not exist.")
        return

    if not os.path.isfile(srt_file):
        print(f"Error: The subtitle file '{srt_file}' does not exist.")
        return

    frame_rate = get_frame_rate(video_file)
    video_dir, video_name = os.path.split(video_file)
    output_file = os.path.join(video_dir, f"subs_{video_name}")

    subtitles_filter = f"subtitles={srt_file}:force_style='FontSize={font_size},PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BackColour=&H80000000&,Outline=2,Shadow=3,MarginV=50'"

    ffmpeg_command = [
        'ffmpeg',
        '-i', video_file,
        '-vf', subtitles_filter,
        '-c:a', 'copy',
        output_file
    ]

    try:
        subprocess.run(ffmpeg_command, check=True)
        print(f"Subtitles burned into video successfully. Output file: '{output_file}'")
    except subprocess.CalledProcessError as e:
        print(f"Error: FFmpeg failed with exit code {e.returncode}")
        print(e.output)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python burn_subtitles_only.py <video_file> <srt_file> [font_size]")
    else:
        video_file = sys.argv[1]
        srt_file = sys.argv[2]
        font_size = int(sys.argv[3]) if len(sys.argv) >= 4 else 20

        burn_subtitles(video_file, srt_file, font_size)
