#!/usr/bin/env python3

import os
import sys
import subprocess

def get_frame_rate(video_file):
    # Use ffprobe to extract the video’s frame rate for SMPTE timecode accuracy
    result = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=r_frame_rate',
         '-of', 'default=noprint_wrappers=1:nokey=1', video_file],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    rate = result.stdout.decode().strip()
    num, denom = map(int, rate.split('/'))
    return num / denom

def burn_subtitles(video_file, srt_file=None, font_size=None, smpte_only=False, subs_only=False, downscale_720=False, force_mp4=False):
    if not os.path.isfile(video_file):
        print(f"Error: The video file '{video_file}' does not exist.")
        return

    frame_rate = get_frame_rate(video_file)
    video_dir, video_name = os.path.split(video_file)
    base_name, _ = os.path.splitext(video_name)

    # Set output filename prefix based on mode:
    # "tc_" = timecode only, "subs_" = subtitles only, "burn_" = both timecode and subs
    output_prefix = "tc_" if smpte_only else "subs_" if subs_only else "burn_"
    ext = ".mp4" if force_mp4 else os.path.splitext(video_file)[1]
    output_file = os.path.join(video_dir, f"{output_prefix}{base_name}{ext}")

    filters = []

    if downscale_720:
        # Important: scale first before adding subtitles to keep them sharp.
        # If subtitles are added before scaling, they’ll be rendered at full res and then downscaled,
        # which can make the text appear blurry—especially noticeable for sighted users.
        filters.append("scale=1280:720")

    if not subs_only:
        # SMPTE timecode overlay in top-left corner using drawtext.
        # Font, size, and box color can be customized here.
        # Note: drawtext does not use libass styling—it's controlled manually.
        filters.append(
            f"drawtext=fontfile=/Library/Fonts/DroidSansMono.ttf:timecode='00\\:00\\:00\\:00':rate={frame_rate}:fontsize=30:"
            "fontcolor=white:x=10:y=10:box=1:boxcolor=0x000000AA"
        )

    if not smpte_only:
        if not os.path.isfile(srt_file):
            print(f"Error: The subtitle file '{srt_file}' does not exist.")
            return

        # Subtitle style customization using libass "force_style" overrides
        # These ensure consistent appearance across systems, regardless of default settings
        style_parts = [
            f"FontSize={font_size if font_size else 20}",          # Text size in points
            "PrimaryColour=&H00FFFFFF&",                           # White text
            "SecondaryColour=&H00FF0000&",                         # (Not used unless karaoke)
            "OutlineColour=&H00000000&",                           # Black outline
            "BackColour=&H80000000&",                              # Semi-transparent black background box
            "Outline=2",                                           # Outline thickness
            "Shadow=3",                                            # Drop shadow depth
            "MarginV=50",                                          # Vertical margin (bottom padding)
            "MarginL=12",                                          # Left padding
            "MarginR=12"                                           # Right padding
        ]
        subtitles_filter = f"subtitles={srt_file}:force_style='{','.join(style_parts)}'"
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
        print("Usage: python burn_subtitles.py <video_file> [<srt_file> [font_size]] [--smpte-only | --subs-only] [--720] [--mp4]")
    elif '--smpte-only' in sys.argv and '--subs-only' in sys.argv:
        print("Error: Cannot use both '--smpte-only' and '--subs-only' at the same time.")
    else:
        video_file = sys.argv[1]
        smpte_only = '--smpte-only' in sys.argv
        subs_only = '--subs-only' in sys.argv
        downscale_720 = '--720' in sys.argv
        force_mp4 = '--mp4' in sys.argv

        srt_file = None
        font_size = None

        if not smpte_only:
            srt_file = sys.argv[2]
            if len(sys.argv) >= 4 and not sys.argv[3].startswith('--'):
                try:
                    font_size = int(sys.argv[3])
                except ValueError:
                    print(f"Warning: Ignoring invalid font size value: {sys.argv[3]}")

        burn_subtitles(video_file, srt_file, font_size, smpte_only, subs_only, downscale_720, force_mp4)
