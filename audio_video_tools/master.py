#!/usr/bin/env python3

import os
import argparse
import subprocess
import tempfile
import shutil

SUPPORTED_FORMATS = ['.mp4', '.mkv', '.wav', '.mp3', '.aac', '.eac3', '.m4a', '.ac3']
BUMPER_SRC = os.path.expanduser("~/audio-vault-assets/bumper.mp3")
SILENCE_SRC = os.path.expanduser("~/audio-vault-assets/silence_1s.mp3")

def ensure_stereo_cbr(input_path, output_path):
    # Ensure 48kHz stereo CBR 192k MP3
    subprocess.run([
        "ffmpeg", "-y", "-i", input_path,
        "-ar", "48000", "-ac", "2", "-b:a", "192k",
        output_path
    ], check=True)

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate, samplerate, highpass, is_audiovault):
    temp_output = tempfile.mktemp(suffix=f".{audio_format}")

    # Build FFmpeg processing chain
    ffmpeg_cmd = ["ffmpeg", "-y", "-i", input_file]
    audio_filters = []
    if highpass:
        audio_filters.append("highpass=f=80")
    if aggressive_compression:
        audio_filters.append("acompressor=threshold=-24dB:ratio=4:attack=5:release=150")
    audio_filters.append(f"acompressor=threshold=-18dB:ratio=3:attack=10:release=200,loudnorm=I={profile['LUFS']}:LRA={profile['LRA']}:TP={profile['TP']}")
    ffmpeg_cmd += ["-af", ",".join(audio_filters)]

    if audio_format == "aac":
        ffmpeg_cmd += ["-c:a", "aac", "-b:a", bitrate, "-ar", str(samplerate)]
    elif audio_format == "eac3":
        ffmpeg_cmd += ["-c:a", "eac3", "-b:a", bitrate, "-ar", str(samplerate)]
    elif audio_format == "mp3":
        ffmpeg_cmd += ["-c:a", "libmp3lame", "-q:a", "2", "-ar", str(samplerate), "-ac", "2"]
    elif audio_format == "wav":
        ffmpeg_cmd += ["-c:a", "pcm_s24le", "-ar", str(samplerate)]
    else:
        raise ValueError(f"Unsupported audio format: {audio_format}")

    ffmpeg_cmd += [temp_output]
    subprocess.run(ffmpeg_cmd, check=True)

    if is_audiovault and audio_format == "mp3":
        fixed_bumper = tempfile.mktemp(suffix=".mp3")
        fixed_silence = tempfile.mktemp(suffix=".mp3")
        ensure_stereo_cbr(BUMPER_SRC, fixed_bumper)
        ensure_stereo_cbr(SILENCE_SRC, fixed_silence)

        concat_txt = tempfile.mktemp(suffix=".txt")
        with open(concat_txt, "w") as f:
            f.write(f"file '{fixed_silence}'\n")
            f.write(f"file '{fixed_bumper}'\n")
            f.write(f"file '{fixed_silence}'\n")
            f.write(f"file '{temp_output}'\n")

        subprocess.run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_txt, "-c", "copy", output_file], check=True)

        os.remove(concat_txt)
        os.remove(fixed_bumper)
        os.remove(fixed_silence)
        os.remove(temp_output)
    else:
        shutil.move(temp_output, output_file)

def get_files_from_directory(directory):
    files = []
    for root, _, filenames in os.walk(directory):
        for filename in filenames:
            if any(filename.endswith(ext) for ext in SUPPORTED_FORMATS):
                files.append(os.path.join(root, filename))
    return files

def main():
    parser = argparse.ArgumentParser(description="Batch Mastering Script for Audio/Video Files")
    parser.add_argument("input", help="Input file or directory to process")
    parser.add_argument("output", help="Output file or directory for processed audio")
    parser.add_argument("--profile", type=str, default="Broadcast TV",
                        choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"],
                        help="Select loudness profile for normalization")
    parser.add_argument("--format", type=str, default=None,
                        choices=["aac", "mp3", "eac3", "wav"],
                        help="Output audio format (overridden if output filename has an extension)")
    parser.add_argument("--bitrate", type=str, default="192k", help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--samplerate", type=int, default=48000, help="Audio sample rate")
    parser.add_argument("--aggressive", action="store_true", help="Apply aggressive compression")
    parser.add_argument("--highpass", action="store_true", help="Apply high-pass filter at 80Hz")
    args = parser.parse_args()

    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))
        profiles["Custom"] = {"LUFS": -abs(lufs), "TP": -abs(tp), "LRA": lra}

    output_ext = os.path.splitext(args.output)[1].lower()
    if output_ext in SUPPORTED_FORMATS:
        args.format = output_ext[1:]
    elif args.profile == "AudioVault":
        args.format = "mp3"
    elif args.format is None:
        args.format = "aac"

    is_audiovault = (args.profile == "AudioVault")

    if os.path.isdir(args.input):
        files = get_files_from_directory(args.input)
        os.makedirs(args.output, exist_ok=True)
        for file in files:
            output_file = os.path.join(args.output, os.path.splitext(os.path.basename(file))[0] + f".{args.format}")
            process_file(file, output_file, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.samplerate, args.highpass, is_audiovault)
    elif os.path.isfile(args.input):
        process_file(args.input, args.output, profiles[args.profile], args.aggressive, args.format, args.bitrate, args.samplerate, args.highpass, is_audiovault)
    else:
        print("Invalid input. Please specify a valid file or directory.")
        return

    print("Batch processing complete!")

if __name__ == "__main__":
    main()
