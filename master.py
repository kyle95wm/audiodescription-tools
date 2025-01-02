#!/usr/bin/env python3

import os
import argparse
import subprocess

# Supported formats
SUPPORTED_FORMATS = ['.mp4', '.mkv', '.wav', '.mp3', '.aac', '.eac3']

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate):
    # Base FFmpeg command
    audio_filter = "acompressor=threshold=-18dB:ratio=3:attack=10:release=200,loudnorm=I={LUFS}:LRA={LRA}:TP={TP}".format(**profile)

    if aggressive_compression:
        audio_filter = "acompressor=threshold=-24dB:ratio=4:attack=5:release=150," + audio_filter

    ffmpeg_cmd = [
        "ffmpeg",
        "-i", input_file,
        "-af", audio_filter
    ]

    # Set audio codec and format
    if audio_format == "aac":
        ffmpeg_cmd += ["-c:a", "aac", "-b:a", bitrate, "-c:v", "copy"]
    elif audio_format == "eac3":
        ffmpeg_cmd += ["-c:a", "eac3", "-b:a", bitrate]
    elif audio_format == "mp3":
        ffmpeg_cmd += ["-c:a", "libmp3lame", "-q:a", "2"]
    elif audio_format == "wav":
        ffmpeg_cmd += [
            "-c:a", "pcm_s24le",  # 24-bit WAV
            "-ar", "48000",       # Set sample rate to 48kHz
            "-write_bext", "1",   # Write BWF metadata
            "-rf64", "auto"       # Allow for larger than 4GB files
        ]
    else:
        raise ValueError(f"Unsupported audio format: {audio_format}")

    # Set output file
    ffmpeg_cmd += [output_file]

    # Execute FFmpeg command
    try:
        subprocess.run(ffmpeg_cmd, check=True)
        print(f"✅ Successfully processed: {output_file}")
    except subprocess.CalledProcessError as e:
        print(f"❌ Error during processing: {e}")

def get_files_from_directory(directory):
    files = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if any(filename.endswith(ext) for ext in SUPPORTED_FORMATS):
                files.append(os.path.join(root, filename))
    return files

def main():
    parser = argparse.ArgumentParser(description="Batch Mastering Script")
    parser.add_argument("input", help="Input file or directory")
    parser.add_argument("output", help="Output file or directory")
    parser.add_argument("--profile", type=str, default="Broadcast TV",
                        choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"],
                        help="Loudness profile")
    parser.add_argument("--format", type=str, default="aac", choices=["aac", "mp3", "eac3", "wav"],
                        help="Output audio format")
    parser.add_argument("--bitrate", type=str, default="192k", help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--aggressive", action="store_true", help="Apply aggressive compression")
    args = parser.parse_args()

    # Define profiles
    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    # Custom profile
    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))
        profiles["Custom"] = {"LUFS": lufs, "TP": tp, "LRA": lra}

    # Determine input type
    if os.path.isdir(args.input):
        files = get_files_from_directory(args.input)
        os.makedirs(args.output, exist_ok=True)  # Ensure output directory exists
        for file in files:
            output_file = os.path.join(args.output, os.path.basename(file))
            process_file(file, output_file, profiles[args.profile], args.aggressive, args.format, args.bitrate)
    elif os.path.isfile(args.input):
        process_file(args.input, args.output, profiles[args.profile], args.aggressive, args.format, args.bitrate)
    else:
        print("Invalid input. Please specify a valid file or directory.")
        return

    print("🔄 Batch processing complete!")

if __name__ == "__main__":
    main()
