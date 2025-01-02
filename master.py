#!/usr/bin/env python3

import os
import argparse
import subprocess

SUPPORTED_FORMATS = ['.mp4', '.mkv', '.wav', '.mp3', '.aac', '.eac3']

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate, highpass):
    # High-pass filter inclusion
    filters = []
    if highpass:
        filters.append("highpass=f=80")
    
    # Compression and Loudness Normalization
    filters.append("acompressor=threshold=-24dB:ratio=4:attack=5:release=150" if aggressive_compression else "acompressor=threshold=-18dB:ratio=3:attack=10:release=200")
    filters.append(f"loudnorm=I={profile['LUFS']}:LRA={profile['LRA']}:TP={profile['TP']}")

    # Join filters
    audio_filter = ",".join(filters)

    ffmpeg_cmd = [
        "ffmpeg",
        "-i", input_file,
        "-af", audio_filter,
        "-c:a", "libmp3lame" if audio_format == "mp3" else "pcm_s24le" if audio_format == "wav" else audio_format,
        "-b:a", bitrate,
        output_file
    ]

    subprocess.run(ffmpeg_cmd, check=True)


def get_files_from_directory(directory):
    return [os.path.join(root, f) for root, _, files in os.walk(directory) for f in files if any(f.endswith(ext) for ext in SUPPORTED_FORMATS)]


def main():
    parser = argparse.ArgumentParser(description="Batch Mastering Script")
    parser.add_argument("input", help="Input file or directory")
    parser.add_argument("output", help="Output file or directory")
    parser.add_argument("--profile", type=str, default="Broadcast TV", choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"], help="Loudness profile")
    parser.add_argument("--format", type=str, default="aac", choices=["aac", "mp3", "eac3", "wav"], help="Output audio format")
    parser.add_argument("--bitrate", type=str, default="192k", help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--aggressive", action="store_true", help="Apply aggressive compression")
    parser.add_argument("--highpass", action="store_true", help="Apply high-pass filter at 80Hz to cut subwoofer frequencies")
    args = parser.parse_args()

    # Define profiles
    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    # Custom profile handling
    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))

        # Correct if positive
        if lufs > 0:
            print(f"⚠️ LUFS value corrected to -{lufs}")
            lufs = -lufs
        if tp > 0:
            print(f"⚠️ True Peak value corrected to -{tp}")
            tp = -tp

        profiles["Custom"] = {"LUFS": lufs, "TP": tp, "LRA": lra}

    # Determine input type
    if os.path.isdir(args.input):
        files = get_files_from_directory(args.input)
        os.makedirs(args.output, exist_ok=True)
        for file in files:
            output_file = os.path.join(args.output, f"{os.path.splitext(os.path.basename(file))[0]}.{args.format}")
            process_file(file, output_file, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass)
    elif os.path.isfile(args.input):
        process_file(args.input, args.output, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass)
    else:
        print("Invalid input. Please specify a valid file or directory.")
        return

    print("Batch processing complete!")


if __name__ == "__main__":
    main()
