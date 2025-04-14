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

def burn_subtitles(video_file, srt_file=None, font_size=None, smpte_only=False, subs_only=False):
    """Burn subtitles and/or SMPTE timecode into the video."""
    if not os.path.isfile(video_file):
        print(f"Error: The video file '{video_file}' does not exist.")
        return

    frame_rate = get_frame_rate(video_file)
    video_dir, video_name = os.path.split(video_file)
    output_prefix = "tc_" if smpte_only else "subs_" if subs_only else "burn_"
    output_file = os.path.join(video_dir, f"{output_prefix}{video_name}")

    filters = []

    if not subs_only:
        filters.append(f"drawtext=fontfile=/Library/Fonts/DroidSansMono.ttf:timecode='00\\:00\\:00\\:00':rate={frame_rate}:fontsize=30:fontcolor=white:x=10:y=10:box=1:boxcolor=0x000000AA")

    if not smpte_only:
        if not os.path.isfile(srt_file):
            print(f"Error: The subtitle file '{srt_file}' does not exist.")
            return

        subtitles_filter = f"subtitles={srt_file}"

        style_parts = [
            f"FontSize={font_size if font_size else 20}",
            "PrimaryColour=&H00FFFFFF&",
            "OutlineColour=&H00000000&",
            "Outline=2",
            "Shadow=3",
            "MarginV=50"
        ]
        subtitles_filter += f":force_style='{','.join(style_parts)}'"

        filters.append(subtitles_filter)

    ffmpeg_command = [
        'ffmpeg',
        '-i', video_file,
        '-vf', ",".join(filters),
        '-c:a', 'copy',
        output_file
    ]

    try:
        subprocess.run(ffmpeg_command, check=True)
        print(f"Subtitles and SMPTE timecode burned into video successfully. Output file: '{output_file}'")
    except subprocess.CalledProcessError as e:
        print(f"Error: FFmpeg failed with exit code {e.returncode}")
        print(e.output)

if __name__ == "__main__":
    if len(sys.argv) < 2 or (len(sys.argv) < 3 and '--smpte-only' not in sys.argv and '--subs-only' not in sys.argv):
        print("Usage: python burn_subtitles.py <video_file> [<srt_file> [font_size]] [--smpte-only | --subs-only]")
    elif '--smpte-only' in sys.argv and '--subs-only' in sys.argv:
        print("Error: Cannot use both '--smpte-only' and '--subs-only' at the same time.")
    else:
        video_file = sys.argv[1]
        smpte_only = '--smpte-only' in sys.argv
        subs_only = '--subs-only' in sys.argv

        srt_file = None
        font_size = None

        if not smpte_only:
            srt_file = sys.argv[2]
            if len(sys.argv) >= 4 and not sys.argv[3].startswith('--'):
                try:
                    font_size = int(sys.argv[3])
                except ValueError:
                    print(f"Warning: Ignoring invalid font size value: {sys.argv[3]}")

        burn_subtitles(video_file, srt_file, font_size, smpte_only, subs_only)
