#!/usr/bin/env python3

import os
import argparse
import subprocess
import tempfile

# Loudness profile
PROFILE = {"LUFS": -16.3, "TP": -2.6, "LRA": 5}

# Asset paths
AVO_HEAD_PATH = os.path.expanduser("~/audio-vault-assets/avo_head.mp3")
AVO_TAIL_PATH = os.path.expanduser("~/audio-vault-assets/avo_tail.mp3")
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

    # Step 1: Normalize and compress
    subprocess.run([
        "ffmpeg", "-y", "-i", input_file,
        "-af", f"acompressor=threshold=-18dB:ratio=3:attack=10:release=200,"
               f"loudnorm=I={PROFILE['LUFS']}:LRA={PROFILE['LRA']}:TP={PROFILE['TP']}",
        "-c:a", "libmp3lame", "-b:a", "192k", "-ar", "48000", "-ac", "2",
        temp_mastered
    ], check=True)

    # Step 2: Ensure all required files exist
    for asset in [AVO_HEAD_PATH, AVO_TAIL_PATH]:
        if not os.path.exists(asset):
            raise FileNotFoundError(f"Missing asset: {asset}")
    if not os.path.exists(SILENCE_PATH):
        print("Silence file not found, generating...")
        os.makedirs(os.path.dirname(SILENCE_PATH), exist_ok=True)
        generate_silence(SILENCE_PATH)

    # Step 3: Force stereo CBR on bumpers and silence
    head_fixed = tempfile.mktemp(suffix=".mp3")
    tail_fixed = tempfile.mktemp(suffix=".mp3")
    silence_fixed = tempfile.mktemp(suffix=".mp3")

    ensure_stereo_cbr(AVO_HEAD_PATH, head_fixed)
    ensure_stereo_cbr(AVO_TAIL_PATH, tail_fixed)
    ensure_stereo_cbr(SILENCE_PATH, silence_fixed)

    # Step 4: Build concat list: head > mastered > silence > tail > silence
    concat_list = tempfile.mktemp(suffix=".txt")
    with open(concat_list, "w") as f:
        f.write(f"file '{head_fixed}'\n")
        f.write(f"file '{temp_mastered}'\n")
        f.write(f"file '{silence_fixed}'\n")
        f.write(f"file '{tail_fixed}'\n")
        f.write(f"file '{silence_fixed}'\n")

    # Step 5: Concatenate all parts
    subprocess.run([
        "ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat_list,
        "-c", "copy", output_file
    ], check=True)

    # Step 6: Cleanup
    for path in [head_fixed, tail_fixed, silence_fixed, concat_list, temp_mastered]:
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
