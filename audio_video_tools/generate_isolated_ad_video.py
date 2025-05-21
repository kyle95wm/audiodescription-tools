#!/usr/bin/env python3

import subprocess
import os
import sys
import urllib.request
from pathlib import Path

def ensure_black_image():
    if not os.path.exists("black.png"):
        print("Generating black background image...")
        subprocess.run([
            "ffmpeg", "-f", "lavfi", "-i", "color=c=black:s=1920x1080",
            "-frames:v", "1", "black.png"
        ])

def generate_video(audio_file, title_line, subtitle_line, footer_line, output_file):
    subtitle_line = subtitle_line.replace("'", "\\'")
    footer_line = footer_line.replace("'", "\\'")
    title_line = title_line.replace("'", "\\'")

    cmd = [
        "ffmpeg",
        "-loop", "1",
        "-framerate", "1",
        "-i", "black.png",
        "-i", audio_file,
        "-vf",
        f"drawtext=font=Arial:text='{title_line}':fontsize=48:fontcolor=white:x=(w-text_w)/2:y=400,"\
        f"drawtext=font=Arial:text='{subtitle_line}':fontsize=36:fontcolor=white:x=(w-text_w)/2:y=500,"\
        f"drawtext=font=Arial:text='{footer_line}':fontsize=24:fontcolor=gray:x=(w-text_w)/2:y=580",
        "-c:v", "libx264",
        "-tune", "stillimage",
        "-c:a", "aac",
        "-b:a", "192k",
        "-shortest",
        "-pix_fmt", "yuv420p",
        output_file
    ]

    subprocess.run(cmd)

def process_directory(input_dir, title_line, footer_line, output_dir):
    for audio_path in sorted(Path(input_dir).glob("*.wav")):
        name = audio_path.stem
        subtitle_line = name.replace("_", " ")
        output_file = os.path.join(output_dir, f"{name}.mp4")
        print(f"\nProcessing: {audio_path.name} → {output_file}")
        generate_video(str(audio_path), title_line, subtitle_line, footer_line, output_file)

def check_for_updates(script_path):
    url = "https://raw.githubusercontent.com/kyle95wm/audiodescription-tools/refs/heads/main/audio_video_tools/generate_isolated_ad_video.py"
    try:
        with urllib.request.urlopen(url) as response:
            latest_code = response.read().decode("utf-8")
        with open(script_path, "r") as current_file:
            current_code = current_file.read()
        if current_code.strip() != latest_code.strip():
            print("\nAn updated version of this script is available.")
            choice = input("Do you want to overwrite this file with the latest version? (y/n): ").strip().lower()
            if choice == "y":
                with open(script_path, "w") as current_file:
                    current_file.write(latest_code)
                print("Script updated. Please re-run it.")
                sys.exit(0)
            else:
                print("Continuing with current version...")
    except Exception as e:
        print(f"Could not check for updates: {e}")

if __name__ == "__main__":
    check_for_updates(__file__)

    mode = input("Run in batch mode? (y/n): ").strip().lower()

    title = input("Main title (e.g. Audio Description Track): ").strip() or "Audio Description Track"
    footer = input("Footer (e.g. Audio Only – Sync with your own copy): ").strip() or "Audio Only – Sync with your own copy"

    ensure_black_image()

    if mode == "y":
        input_dir = input("Path to folder of audio files: ").strip()
        output_dir = input("Output folder for videos: ").strip() or "output"
        os.makedirs(output_dir, exist_ok=True)
        process_directory(input_dir, title, footer, output_dir)
    else:
        audio = input("Path to a single AD audio file (WAV or MP3): ").strip()
        if not os.path.isfile(audio):
            print("File not found.")
            sys.exit(1)

        subtitle = input("Subtitle (e.g. Earth to Echo (2014)): ").strip() or "Unknown Title"
        output = input("Output filename (e.g. ad_video.mp4): ").strip() or "ad_video.mp4"
        generate_video(audio, title, subtitle, footer, output)
