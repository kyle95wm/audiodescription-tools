#!/usr/bin/env python3

import os
import argparse
import subprocess
import tempfile
import shutil

# Hardcoded loudness profile for AudioVault
PROFILE = {"LUFS": -16.3, "TP": -2.6, "LRA": 5}

# Default paths for bumper and silence
BUMPER_PATH = os.path.expanduser("~/audio-vault-assets/bumper.mp3")
SILENCE_PATH = os.path.expanduser("~/audio-vault-assets/silence_1s.mp3")

def generate_silence(path):
    subprocess.run([
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
        "-t", "1",
        "-acodec", "libmp3lame", "-b:a", "192k",
        path
    ], check=True)

def ensure_stereo_cbr(input_path, output_path):
    subprocess.run([
        "ffmpeg", "-y", "-i", input_path,
        "-ar", "48000", "-ac", "2", "-b:a", "192k",
        output_path
    ], check=True)

def process_file(input_file, output_file):
    temp_mastered = tempfile.mktemp(suffix=".mp3")

    # Step 1: Process and normalize the main file
    ffmpeg_cmd = [
        "ffmpeg", "-y", "-i", input_file,
        "-af", f"acompressor=threshold=-18dB:ratio=3:attack=10:release=200,"
               f"loudnorm=I={PROFILE['LUFS']}:LRA={PROFILE['LRA']}:TP={PROFILE['TP']}",
        "-c:a", "libmp3lame", "-b:a", "192k", "-ar", "48000", "-ac", "2",
        temp_mastered
    ]
    subprocess.run(ffmpeg_cmd, check=True)

    # Step 2: Ensure bumper/silence files exist
    if not os.path.exists(BUMPER_PATH):
        raise FileNotFoundError(f"Missing bumper file at {BUMPER_PATH}")
    if not os.path.exists(SILENCE_PATH):
        print("Silence file not found, generating...")
        os.makedirs(os.path.dirname(SILENCE_PATH), exist_ok=True)
        generate_silence(SILENCE_PATH)

    # Step 3: Force stereo CBR for bumper/silence
    fixed_bumper = tempfile.mktemp(suffix=".mp3")
    fixed_silence = tempfile.mktemp(suffix=".mp3")
    ensure_stereo_cbr(BUMPER_PATH, fixed_bumper)
    ensure_stereo_cbr(SILENCE_PATH, fixed_silence)

    # Step 4: Concat silence > bumper > silence > mastered track
    concat_txt = tempfile.mktemp(suffix=".txt")
    with open(concat_txt, "w") as f:
        f.write(f"file '{fixed_silence}'\n")
        f.write(f"file '{fixed_bumper}'\n")
        f.write(f"file '{fixed_silence}'\n")
        f.write(f"file '{temp_mastered}'\n")

    subprocess.run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_txt,
        "-c", "copy", output_file
    ], check=True)

    # Clean up
    for path in [fixed_bumper, fixed_silence, concat_txt, temp_mastered]:
        if os.path.exists(path):
            os.remove(path)

    print("Mastering complete:", output_file)

def main():
    parser = argparse.ArgumentParser(description="AudioVault Mastering Tool")
    parser.add_argument("input", help="Input WAV file")
    parser.add_argument("output", help="Output MP3 file")
    args = parser.parse_args()

    if not os.path.isfile(args.input):
        print("Invalid input file.")
        return

    process_file(args.input, args.output)

if __name__ == "__main__":
    main()