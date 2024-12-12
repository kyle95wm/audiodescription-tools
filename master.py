import argparse
import subprocess
import json


def get_input(prompt, default=None):
    """Get user input with an optional default value."""
    value = input(f"{prompt} [{'Default: ' + str(default) if default else ''}]: ").strip()
    return value if value else default


def measure_dlra(input_file):
    """Measure Dialogue Loudness Range using FFmpeg's ebur128 filter."""
    print("\nMeasuring Dialogue Loudness Range (DLRA)...")
    command = [
        "ffmpeg",
        "-i", input_file,
        "-filter_complex", "ebur128=framelog=verbose",
        "-f", "null",
        "-"
    ]
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError:
        print("\nAn error occurred while measuring DLRA. Ensure the input file is valid.")


def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(
        description="Normalize and master audio/video files with customizable loudness, true peak, and loudness range."
    )
    parser.add_argument("input_file", help="Path to the input audio or video file")
    parser.add_argument("output_file", help="Path to the output mastered file")
    args = parser.parse_args()

    # Step 1: Measure DLRA (optional)
    measure_choice = get_input("\nWould you like to measure DLRA before mastering? (y/n)", "n")
    if measure_choice.lower() == "y":
        measure_dlra(args.input_file)

    # Step 2: Choose audio compression type
    print("\nChoose audio format:")
    print("1. Compressed AAC (Default for MP4)")
    print("2. Uncompressed PCM (WAV-like quality)")
    print("3. Compressed MP3")
    print("4. Compressed EAC-3 (Dolby Digital Plus)")
    audio_map = {"1": "aac", "2": "pcm_s24le", "3": "libmp3lame", "4": "eac3"}
    audio_choice = get_input("Enter your choice (1/2/3/4)", "1")
    audio_codec = audio_map.get(audio_choice, "aac")

    # Step 3: Handle profiles
    print("\nChoose a loudness profile:")
    print("1. Broadcast TV (-24 LUFS, -2 dBTP, 6 LRA)")
    print("2. Streaming Platforms (-16 LUFS, -1 dBTP, 6 LRA)")
    print("3. Netflix (-27 LUFS, -2 dBTP, DLRA ≤10 LU)")
    print("4. YouTube (-14 LUFS, -1 dBTP, ≤8 LRA)")
    if audio_choice == "3":  # Only show AudioVault for MP3
        print("5. AudioVault (-16.3 LUFS, -2.6 dBTP, 5 LRA, MP3-only)")
    print("6. Spotify (-14 LUFS, -1 dBTP, ≤8 LRA)")
    print("7. Apple Podcasts (-16 LUFS, -1 dBTP, ≤8 LRA)")
    print("8. Custom (Specify your own values)")
    profile_choice = get_input("Enter your choice (1/2/3/4/5/6/7/8)", "1")

    # Step 4: Set loudness parameters
    loudness_map = {
        "1": {"I": "-24", "TP": "-2", "LRA": "6"},
        "2": {"I": "-16", "TP": "-1", "LRA": "6"},
        "3": {"I": "-27", "TP": "-2", "LRA": "6"},
        "4": {"I": "-14", "TP": "-1", "LRA": "8"},
        "5": {"I": "-16.3", "TP": "-2.6", "LRA": "5"},
        "6": {"I": "-14", "TP": "-1", "LRA": "8"},
        "7": {"I": "-16", "TP": "-1", "LRA": "8"},
    }

    if profile_choice in loudness_map:
        profile = loudness_map[profile_choice]
        target_lufs = profile["I"]
        target_tp = profile["TP"]
        target_lra = profile["LRA"]
    else:  # Custom Profile
        print("\nCustom Profile Selected!")
        target_lufs = get_input("Enter target integrated loudness (e.g., -24)", "-24")
        target_tp = get_input("Enter true peak limit (e.g., -2)", "-2")
        target_lra = get_input("Enter loudness range (e.g., 6)", "6")

    # Step 5: Add optional aggressive compression
    apply_compression = get_input("\nWould you like to add aggressive compression? (y/n)", "n")
    if apply_compression.lower() == "y":
        compression_filter = "acompressor=threshold=-18dB:ratio=3:attack=10:release=200,"
    else:
        compression_filter = ""

    # Step 6: Handle EAC-3-specific options
    eac3_bitrate = None
    dialnorm = None
    if audio_codec == "eac3":
        dialnorm = round(float(target_lufs))  # Set Dialnorm to match loudness target
        eac3_bitrate = get_input("Enter EAC-3 bitrate (Default: 192k)", "192k")

    # Step 7: Loudness normalization
    print("\nProcessing your file (loudness normalization)...")
    ffmpeg_command = [
        "ffmpeg",
        "-i", args.input_file,
        "-af",
        f"{compression_filter}loudnorm=I={target_lufs}:LRA={target_lra}:TP={target_tp}",
    ]

    if audio_choice == "3":  # MP3-specific settings
        mp3_bitrate = get_input("Enter MP3 bitrate (e.g., 128k, 192k, 320k)", "192k")
        ffmpeg_command.extend(["-vn", "-c:a", "libmp3lame", "-b:a", mp3_bitrate])
    elif audio_choice == "4":  # EAC-3-specific settings
        ffmpeg_command.extend([
            "-c:v", "copy",
            "-c:a", "eac3",
            "-b:a", eac3_bitrate,
            "-metadata", f"dialnorm={dialnorm}"
        ])
    else:
        ffmpeg_command.extend(["-c:v", "copy", "-c:a", audio_codec])

    ffmpeg_command.append(args.output_file)

    print("Executing FFmpeg command:", " ".join(ffmpeg_command))  # Debugging: Show full command
    try:
        subprocess.run(ffmpeg_command, check=True)
        print(f"\nMastering complete! Your file has been saved to {args.output_file}")
    except subprocess.CalledProcessError:
        print("\nAn error occurred during processing. Please check your input file and try again.")


if __name__ == "__main__":
    main()
