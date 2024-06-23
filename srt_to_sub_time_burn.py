#!/usr/bin/env python3

import os
import sys
import subprocess

def get_frame_rate(video_file):
    # Use FFmpeg to get the frame rate of the video
    result = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=r_frame_rate', '-of', 'default=noprint_wrappers=1:nokey=1', video_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    rate = result.stdout.decode().strip()
    # Calculate the frame rate
    num, denom = map(int, rate.split('/'))
    return num / denom

def burn_subtitles_with_background_and_timecode(video_file, srt_file, font_size=None, opacity=0.7):
    # Ensure the provided video and SRT files exist
    if not os.path.isfile(video_file):
        print(f"Error: The video file '{video_file}' does not exist.")
        return
    if not os.path.isfile(srt_file):
        print(f"Error: The subtitle file '{srt_file}' does not exist.")
        return

    # Get the frame rate of the video
    frame_rate = get_frame_rate(video_file)

    # Construct the output file name
    video_dir, video_name = os.path.split(video_file)
    output_file = os.path.join(video_dir, f"burn_{video_name}")

    # Construct the subtitles filter
    subtitles_filter = f"subtitles={srt_file}"
    if font_size:
        subtitles_filter += f":force_style='FontSize={font_size},PrimaryColour=&H00FFFFFF&,OutlineColour=&H00000000&,BackColour=&H80000000&,Outline=2,Shadow=3,MarginV=50'"

    # Construct the FFmpeg command
    ffmpeg_command = [
        'ffmpeg',
        '-i', video_file,
        '-vf', f"drawtext=fontfile=/Library/Fonts/DroidSansMono.ttf:timecode='00\\:00\\:00\\:00':rate={frame_rate}:fontsize=72:fontcolor=white:x=10:y=10:box=1:boxcolor=0x000000AA,drawbox=x=0:y=ih-70:w=iw:h=60:color=black@{opacity}:t=fill,{subtitles_filter}",
        '-c:a', 'copy',
        output_file
    ]

    # Run the FFmpeg command
    try:
        subprocess.run(ffmpeg_command, check=True)
        print(f"Subtitles with background and SMPTE timecode burned into video successfully. Output file: '{output_file}'")
    except subprocess.CalledProcessError as e:
        print(f"Error: FFmpeg failed with exit code {e.returncode}")
        print(e.output)

if __name__ == "__main__":
    if len(sys.argv) < 3 or len(sys.argv) > 5:
        print("Usage: python burn_subtitles_with_background_and_timecode.py <video_file> <srt_file> [font_size] [opacity]")
    else:
        video_file = sys.argv[1]
        srt_file = sys.argv[2]
        font_size = int(sys.argv[3]) if len(sys.argv) >= 4 else None
        opacity = float(sys.argv[4]) if len(sys.argv) == 5 else 0.7
        burn_subtitles_with_background_and_timecode(video_file, srt_file, font_size, opacity)