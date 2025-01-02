#!/usr/bin/env python3
import os
import argparse
import subprocess

# Supported formats
SUPPORTED_FORMATS = ['.mp4', '.mkv', '.wav', '.mp3', '.aac', '.eac3']

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate, highpass):
    # Base FFmpeg command
    audio_filter = ""
    
    if highpass:
        audio_filter += "highpass=f=80,"

    if aggressive_compression:
        audio_filter += "acompressor=threshold=-24dB:ratio=4:attack=5:release=150,"

    audio_filter += "acompressor=threshold=-18dB:ratio=3:attack=10:release=200,"
    audio_filter += f"loudnorm=I={profile['LUFS']}:LRA={profile['LRA']}:TP={profile['TP']}"

    ffmpeg_cmd = [
        "ffmpeg",
        "-i", input_file,
        "-af", audio_filter,
    ]

    # Set audio codec and format
    if audio_format == "aac":
        ffmpeg_cmd += ["-c:a", "aac", "-b:a", bitrate]
    elif audio_format == "eac3":
        ffmpeg_cmd += ["-c:a", "eac3", "-b:a", bitrate]
    elif audio_format == "mp3":
        ffmpeg_cmd += ["-c:a", "libmp3lame", "-b:a", bitrate]
    elif audio_format == "wav":
        ffmpeg_cmd += ["-c:a", "pcm_s24le", "-write_bext", "1", "-rf64", "auto"]
    else:
        raise ValueError(f"Unsupported audio format: {audio_format}")
    
    ffmpeg_cmd += [output_file]
    subprocess.run(ffmpeg_cmd, check=True)
    print(f"✅ Processed: {output_file}")


def mux_audio_to_video(input_video, processed_audio, output_video):
    ffmpeg_cmd = [
        "ffmpeg", "-i", input_video,
        "-i", processed_audio,
        "-c:v", "copy",  # Copy video stream without re-encoding
        "-map", "0:v:0",  # Map video from input 0
        "-map", "1:a:0",  # Map audio from input 1
        "-shortest",
        output_video
    ]
    subprocess.run(ffmpeg_cmd, check=True)
    print(f"✅ Muxed: {output_video}")


def get_files_from_directory(directory):
    files = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if any(filename.endswith(ext) for ext in SUPPORTED_FORMATS):
                files.append(os.path.join(root, filename))
    return files


def main():
    parser = argparse.ArgumentParser(description="Batch Audio Mastering and Muxing Script")
    parser.add_argument("input", help="Input file or directory")
    parser.add_argument("output", help="Output file or directory")
    parser.add_argument("--profile", type=str, default="Broadcast TV", choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"], help="Loudness profile")
    parser.add_argument("--format", type=str, default="aac", choices=["aac", "mp3", "eac3", "wav"], help="Output audio format")
    parser.add_argument("--bitrate", type=str, default="192k", help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--aggressive", action="store_true", help="Apply aggressive compression")
    parser.add_argument("--highpass", action="store_true", help="Apply high pass filter at 80 Hz to cut subwoofer frequencies")
    args = parser.parse_args()

    # Define profiles
    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    # Handle Custom Profile
    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))

        # Automatically correct positive LUFS and TP values
        lufs = lufs if lufs < 0 else -abs(lufs)
        tp = tp if tp < 0 else -abs(tp)

        profiles["Custom"] = {"LUFS": lufs, "TP": tp, "LRA": lra}

    # Determine if input is directory or file
    if os.path.isdir(args.input):
        files = get_files_from_directory(args.input)
        os.makedirs(args.output, exist_ok=True)
        for file in files:
            base_name = os.path.splitext(os.path.basename(file))[0]
            temp_audio_file = os.path.join(args.output, f"{base_name}_processed.{args.format}")
            output_video_file = os.path.join(args.output, f"{base_name}_muxed.mp4")
            
            process_file(file, temp_audio_file, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass)
            mux_audio_to_video(file, temp_audio_file, output_video_file)
    elif os.path.isfile(args.input):
        base_name = os.path.splitext(os.path.basename(args.input))[0]
        temp_audio_file = f"{base_name}_processed.{args.format}"
        process_file(args.input, temp_audio_file, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.highpass)
        
        # If output is a video, perform muxing
        if args.output.endswith(('.mp4', '.mkv')):
            mux_audio_to_video(args.input, temp_audio_file, args.output)
        else:
            os.rename(temp_audio_file, args.output)
    else:
        print("Invalid input. Please specify a valid file or directory.")
        return

    print("Batch processing complete!")


if __name__ == "__main__":
    main()
