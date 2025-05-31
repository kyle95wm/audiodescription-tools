#!/usr/bin/env python3

import os
import sys
import subprocess

def get_frame_rate(video_file):
    result = subprocess.run(
        ['ffprobe', '-v', 'error', '-select_streams', 'v:0',
         '-show_entries', 'stream=r_frame_rate',
         '-of', 'default=noprint_wrappers=1:nokey=1', video_file],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    rate = result.stdout.decode().strip()
    num, denom = map(int, rate.split('/'))
    return num / denom

def burn_subtitles(video_file, srt_file=None, font_size=None, smpte_only=False, subs_only=False, downscale_720=False, force=False):
    frame_rate = get_frame_rate(video_file)
    base_name, _ = os.path.splitext(os.path.basename(video_file))

    output_prefix = "tc_" if smpte_only else "subs_" if subs_only else "burn_"
    output_file = os.path.join("output", f"{output_prefix}{base_name}.mp4")

    if os.path.isfile(output_file) and not force:
        print(f"⏩ Skipping {base_name} (already processed)")
        return

    filters = []

    if downscale_720:
        filters.append("scale=1280:720")

    if not subs_only:
        filters.append(
            f"drawtext=fontfile=/Library/Fonts/DroidSansMono.ttf:timecode='00\\:00\\:00\\:00':rate={frame_rate}:fontsize=30:"
            "fontcolor=white:x=10:y=10:box=1:boxcolor=0x000000AA"
        )

    if not smpte_only and srt_file and os.path.isfile(srt_file):
        style_parts = [
            f"FontSize={font_size if font_size else 20}",
            "PrimaryColour=&H00FFFFFF&",
            "SecondaryColour=&H00FF0000&",
            "OutlineColour=&H00000000&",
            "BackColour=&H80000000&",
            "Outline=2",
            "Shadow=3",
            "MarginV=50",
            "MarginL=12",
            "MarginR=12"
        ]
        srt_file_clean = os.path.abspath(srt_file).replace('\\', '/').replace("'", r"\\'")
        force_style = ','.join(style_parts).replace("'", r"\\'")
        filters.append(f"subtitles='{srt_file_clean}':force_style='{force_style}'")

    ffmpeg_command = [
        'ffmpeg', '-y',
        '-i', video_file,
        '-vf', ",".join(filters),
        '-c:a', 'copy',
        output_file
    ]

    try:
        subprocess.run(ffmpeg_command, check=True)
        print(f"✔ Done: {output_file}")
    except subprocess.CalledProcessError as e:
        print(f"✖ FFmpeg failed on {video_file} (exit code {e.returncode})")

def batch_process(font_size=None, smpte_only=False, subs_only=False, downscale_720=False, force=False):
    os.makedirs("output", exist_ok=True)
    video_exts = ['.mp4', '.mkv', '.mov']
    for file in os.listdir():
        if not os.path.isfile(file):
            continue

        base, ext = os.path.splitext(file)
        if ext.lower() not in video_exts:
            continue

        srt_file = f"{base}.srt"
        if not smpte_only and not os.path.isfile(srt_file):
            print(f"Skipping {file} (no matching SRT found)")
            continue

        burn_subtitles(file, srt_file, font_size, smpte_only, subs_only, downscale_720, force)

if __name__ == "__main__":
    args = sys.argv[1:]

    smpte_only = '--smpte-only' in args
    subs_only = '--subs-only' in args
    downscale_720 = '--720' in args
    batch_mode = '--batch' in args
    force_overwrite = '--force' in args

    if smpte_only and subs_only:
        print("Error: Cannot use both '--smpte-only' and '--subs-only' together.")
        sys.exit(1)

    font_size = None
    positional = [arg for arg in args if not arg.startswith('--') and not arg.isdigit()]
    font_args = [arg for arg in args if arg.isdigit()]
    if font_args:
        font_size = int(font_args[0])

    os.makedirs("output", exist_ok=True)

    if batch_mode:
        batch_process(font_size, smpte_only, subs_only, downscale_720, force_overwrite)
    elif len(positional) >= 1:
        video_file = positional[0]
        srt_file = positional[1] if len(positional) > 1 else None
        if not smpte_only and not srt_file:
            print("Error: Subtitle file required unless using --smpte-only")
            sys.exit(1)
        burn_subtitles(video_file, srt_file, font_size, smpte_only, subs_only, downscale_720, force_overwrite)
    else:
        print("Usage:")
        print("  python burn_subtitles.py <video_file> <srt_file> [font_size] [--smpte-only | --subs-only] [--720] [--force]")
        print("  python burn_subtitles.py --batch [font_size] [--smpte-only | --subs-only] [--720] [--force]")
