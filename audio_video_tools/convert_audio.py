#!/usr/bin/env python3

# Script hasn't been tested yet

import sys
import subprocess
from pathlib import Path
import argparse

def convert_to_wav(input_path, output_dir, downmix=None, dolby_downmix=False, dry_run=False):
    input_path = Path(input_path)
    output_file = output_dir / f"{input_path.stem}.wav"

    if output_file.exists():
        print(f"Skipping {input_path.name}, already converted.")
        return

    print(f"Converting {input_path.name} -> {output_file.name}")

    cmd = [
        "ffmpeg",
        "-i", str(input_path),
        "-ar", "48000",         # 48kHz sample rate
        "-acodec", "pcm_s24le", # 24-bit WAV
    ]

    # Handle downmixing
    if downmix == "mono":
        cmd += ["-ac", "1"]
    elif downmix == "stereo":
        if dolby_downmix:
            # Dolby Pro Logic-style downmix
            cmd += [
                "-ac", "2",
                "-af", "pan=stereo|c0=FL+0.707*FC+0.707*BL+0.707*SL+0.707*LFE|c1=FR+0.707*FC+0.707*BR+0.707*SR+0.707*LFE"
            ]
        else:
            # ITU-style downmix
            cmd += [
                "-ac", "2",
                "-af", "pan=stereo|c0=0.707*FL+0.707*FC+0.707*BL|c1=0.707*FR+0.707*FC+0.707*BR"
            ]

    cmd.append(str(output_file))

    if dry_run:
        print(" ".join(cmd))
    else:
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)

def main():
    parser = argparse.ArgumentParser(
        prog="convert_audio.py",
        description="""
Convert one or many audio files (like .eac3, .ac3, .m4a, .mp3, .wav) to 48kHz 24-bit WAV format.

Preserves the original channel layout by default, or optionally downmixes to mono or stereo.
Supports standard stereo (ITU) and Dolby Pro Logic-style downmixing.

Examples:
  # Convert a single file, preserve channel count
  python convert_audio.py input.ac3

  # Convert all files in a folder, downmix to stereo (ITU)
  python convert_audio.py input_folder --downmix stereo

  # Convert a folder using Dolby-style stereo downmix
  python convert_audio.py input_folder --downmix stereo --dolby-downmix

  # Preview the FFmpeg commands without doing any processing
  python convert_audio.py input_folder --dry-run
""",
        formatter_class=argparse.RawTextHelpFormatter
    )

    parser.add_argument("input", help="Input file or folder")
    parser.add_argument("output", nargs="?", default="converted", help="Output folder")
    parser.add_argument("--downmix", choices=["mono", "stereo"], help="Optional downmixing")
    parser.add_argument("--dolby-downmix", action="store_true", help="Apply Dolby Pro Logic-style stereo downmixing")
    parser.add_argument("--dry-run", action="store_true", help="Show ffmpeg commands without running them")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output)
    output_dir.mkdir(exist_ok=True)

    files = []
    if input_path.is_file():
        files = [input_path]
    elif input_path.is_dir():
        for ext in (".eac3", ".ac3", ".m4a", ".mp3", ".wav"):
            files.extend(input_path.glob(f"*{ext}"))
    else:
        print("Invalid input path.")
        return

    for file in files:
        convert_to_wav(file, output_dir, args.downmix, args.dolby_downmix, args.dry_run)

if __name__ == "__main__":
    main()
