#!/usr/bin/env python3

import os
import argparse
import subprocess

# Supported input/output formats
SUPPORTED_FORMATS = ['.mp4', '.mkv', '.wav', '.mp3', '.aac', '.eac3', '.m4a', '.ac3']

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate, highpass, samplerate):
    """
    Process an individual file by extracting, applying compression and loudness normalization,
    and exporting audio to the specified format.
    """
    
    # Base FFmpeg command for audio extraction and processing
    ffmpeg_cmd = [
        "ffmpeg",
        "-i", input_file,
    ]

    # Construct audio filter chain
    audio_filters = []
    
    # Apply high-pass filter at 80Hz if the switch is enabled
    if highpass:
        audio_filters.append("highpass=f=80")

    # Apply aggressive compression first if enabled
    if aggressive_compression:
        audio_filters.append("acompressor=threshold=-24dB:ratio=4:attack=5:release=150")
    
    # Standard compression and loudness normalization
    audio_filters.append(f"acompressor=threshold=-18dB:ratio=3:attack=10:release=200,loudnorm=I={profile['LUFS']}:LRA={profile['LRA']}:TP={profile['TP']}")
    
    # Add audio filters to the FFmpeg command
    ffmpeg_cmd += ["-af", ",".join(audio_filters)]

    # Set audio codec, sample rate, and format based on user selection
    if audio_format == "aac":
        ffmpeg_cmd += ["-c:a", "aac", "-b:a", bitrate, "-ar", str(samplerate)]
    elif audio_format == "eac3":
        ffmpeg_cmd += ["-c:a", "eac3", "-b:a", bitrate, "-ar", str(samplerate)]
    elif audio_format == "mp3":
        ffmpeg_cmd += ["-c:a", "libmp3lame", "-q:a", "2", "-ar", str(samplerate)]
    elif audio_format == "wav":
        ffmpeg_cmd += ["-c:a", "pcm_s24le", "-ar", str(samplerate)]  # 24-bit WAV by default
    else:
        raise ValueError(f"Unsupported audio format: {audio_format}")
    
    # Set output file path
    ffmpeg_cmd += [output_file]

    # Execute the FFmpeg command and check for errors
    subprocess.run(ffmpeg_cmd, check=True)

def get_files_from_directory(directory):
    """
    Recursively collect all files in a directory that match the supported formats.
    """
    files = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if any(filename.endswith(ext) for ext in SUPPORTED_FORMATS):
                files.append(os.path.join(root, filename))
    return files

def main():
    # Argument parser setup
    parser = argparse.ArgumentParser(description="Batch Mastering Script for Audio/Video Files")
    parser.add_argument("input", help="Input file or directory to process")
    parser.add_argument("output", help="Output file or directory for processed audio")
    parser.add_argument("--profile", type=str, default="Broadcast TV",
                        choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"],
                        help="Select loudness profile for normalization")
    parser.add_argument("--format", type=str, default=None,
                        choices=["aac", "mp3", "eac3", "wav"],
                        help="Output audio format (overridden if output filename has an extension)")
    parser.add_argument("--bitrate", type=str, default="192k",
                        help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--samplerate", type=int, default=48000,
                        help="Audio sample rate (e.g., 44100, 48000, 96000)")
    parser.add_argument("--aggressive", action="store_true",
                        help="Apply aggressive compression before normalization")
    parser.add_argument("--highpass", action="store_true",
                        help="Apply high-pass filter at 80Hz to remove subwoofer content")
    args = parser.parse_args()

    # Pre-defined loudness profiles
    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    # Custom profile input handling
    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))

        # Correct potential positive values by converting them to negative
        profiles["Custom"] = {
            "LUFS": -abs(lufs),
            "TP": -abs(tp),
            "LRA": lra,
        }

    # Determine output format
    output_ext = os.path.splitext(args.output)[1].lower()
    if output_ext in SUPPORTED_FORMATS:
        args.format = output_ext[1:]  # Strip the dot from extension
    elif args.profile == "AudioVault":
        args.format = "mp3"  # Force MP3 for AudioVault if no extension overrides it
    elif args.format is None:
        args.format = "aac"  # Default format if nothing is specified

    # Determine if input is a directory or single file
    if os.path.isdir(args.input):
        files = get_files_from_directory(args.input)
        os.makedirs(args.output, exist_ok=True)  # Ensure output directory exists

        # Process each file in the directory
        for file in files:
            output_file = os.path.join(args.output, os.path.splitext(os.path.basename(file))[0] + f".{args.format}")
            process_file(file, output_file, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass, args.samplerate)
    elif os.path.isfile(args.input):
        # Process single file
        process_file(args.input, args.output, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass, args.samplerate)
    else:
        print("Invalid input. Please specify a valid file or directory.")
        return

    print("Batch processing complete!")

if __name__ == "__main__":
    main()
