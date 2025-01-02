#!/usr/bin/env python3

import os
import argparse
import subprocess

# Supported video formats for processing
SUPPORTED_FORMATS = ['.mp4', '.mkv', '.mov']

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate, highpass):
    """
    Process the audio from the input file by applying loudness normalization, compression, 
    and optional high-pass filtering. The processed audio is muxed back into the video without re-encoding the video.

    Args:
        input_file (str): Path to the input video file.
        output_file (str): Path to the output video file with processed audio.
        profile (dict): Loudness profile (LUFS, TP, LRA).
        aggressive_compression (bool): Whether to apply aggressive compression.
        audio_format (str): Desired audio output format (aac, mp3, eac3, wav).
        bitrate (str): Audio bitrate (e.g., 192k).
        highpass (bool): Apply a high-pass filter at 80Hz to remove low frequencies.
    """

    # Step 1: Build audio filter chain
    filters = []

    # Apply high-pass filter (if specified)
    if highpass:
        filters.append("highpass=f=80")
    
    # Apply aggressive compression (optional)
    if aggressive_compression:
        filters.append("acompressor=threshold=-24dB:ratio=4:attack=5:release=150")

    # Standard compression and loudness normalization
    filters.append("acompressor=threshold=-18dB:ratio=3:attack=10:release=200")
    filters.append(f"loudnorm=I={profile['LUFS']}:LRA={profile['LRA']}:TP={profile['TP']}")

    # Join filters into a single string for FFmpeg
    filter_chain = ",".join(filters)

    # Temporary audio file (processed audio only)
    temp_audio = f"{os.path.splitext(output_file)[0]}_temp.{audio_format}"

    # Step 2: Extract and process audio
    ffmpeg_cmd = [
        "ffmpeg",
        "-i", input_file,                # Input video file
        "-af", filter_chain,             # Apply audio filters
        "-c:a", f"lib{audio_format}" if audio_format != 'wav' else "pcm_s24le",  # Audio codec
        "-b:a", bitrate,                 # Bitrate for output audio
        temp_audio                       # Temporary processed audio file
    ]

    print(f"🔄 Processing audio from: {input_file}")
    subprocess.run(ffmpeg_cmd, check=True)  # Execute the FFmpeg command

    # Step 3: Mux the processed audio with the original video (without re-encoding video)
    ffmpeg_mux_cmd = [
        "ffmpeg",
        "-i", input_file,                # Input original video
        "-i", temp_audio,                # Input processed audio
        "-c:v", "copy",                  # Copy the video stream without re-encoding
        "-map", "0:v:0",                 # Map the video stream from the original input
        "-map", "1:a:0",                 # Map the audio stream from the processed audio
        "-shortest",                     # Ensure the muxed file ends when the shortest stream ends
        output_file                      # Output final video file
    ]

    print(f"🔄 Muxing processed audio into: {output_file}")
    subprocess.run(ffmpeg_mux_cmd, check=True)

    # Step 4: Remove the temporary audio file after muxing
    os.remove(temp_audio)
    print(f"🗑️ Removed temporary audio file: {temp_audio}")


def get_files_from_directory(directory):
    """
    Recursively get all video files from the specified directory.

    Args:
        directory (str): Path to the input directory.
    
    Returns:
        list: List of file paths for all supported video formats.
    """
    files = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if any(filename.endswith(ext) for ext in SUPPORTED_FORMATS):
                files.append(os.path.join(root, filename))
    return files


def main():
    """
    Main entry point of the script. Handles argument parsing, profile selection,
    and batch processing of files.
    """
    # Step 1: Argument parser for CLI options
    parser = argparse.ArgumentParser(description="Batch Audio Mastering and Muxing Script")
    parser.add_argument("input", help="Input file or directory")
    parser.add_argument("output", help="Output file or directory")
    parser.add_argument("--profile", type=str, default="Broadcast TV", 
                        choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"], 
                        help="Loudness profile")
    parser.add_argument("--format", type=str, default="mp3", 
                        choices=["aac", "mp3", "eac3", "wav"], 
                        help="Output audio format")
    parser.add_argument("--bitrate", type=str, default="192k", 
                        help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--aggressive", action="store_true", 
                        help="Apply aggressive compression")
    parser.add_argument("--highpass", action="store_true", 
                        help="Apply high-pass filter at 80Hz (cuts subwoofer)")
    args = parser.parse_args()

    # Step 2: Define loudness profiles (LUFS, TP, LRA values)
    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    # Step 3: Handle custom profile input (prompt for LUFS, TP, LRA values)
    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))

        # Correct positive values to negative
        lufs = lufs if lufs <= 0 else -lufs
        tp = tp if tp <= 0 else -tp

        profiles["Custom"] = {"LUFS": lufs, "TP": tp, "LRA": lra}

    # Step 4: Process input (file or directory)
    if os.path.isdir(args.input):
        files = get_files_from_directory(args.input)
        os.makedirs(args.output, exist_ok=True)  # Create output directory if not exists
        for file in files:
            output_file = os.path.join(args.output, os.path.basename(file))
            process_file(file, output_file, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass)
    elif os.path.isfile(args.input):
        process_file(args.input, args.output, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass)
    else:
        print("Invalid input. Please specify a valid file or directory.")
        return

    print("✅ Batch processing complete!")


if __name__ == "__main__":
    main()
