#!/usr/bin/env python3

import os
import subprocess
import argparse

PROFILES = {
    "1": ("Broadcast TV", "-24", "8", "-2"),
    "2": ("Streaming Platforms", "-23", "10", "-1"),
    "3": ("Netflix", "-27", "9", "-2"),
    "4": ("YouTube", "-14", "7", "-1"),
    "5": ("AudioVault", "-16.3", "5", "-2.6"),
}

FORMATS = {
    "1": "aac",
    "2": "mp3",
    "3": "eac3",
    "4": "wav"
}

def select_option(prompt, options, default=None):
    print(prompt)
    for key, value in options.items():
        print(f"{key}. {value}")
    choice = input(f"Select option [{default}]: ")
    return options.get(choice, options[default])


def process_file(input_file, output_file, profile, aggressive, audio_format, bitrate):
    profile_name, i_lufs, lra, tp = PROFILES[profile]
    compression = 'acompressor=threshold=-18dB:ratio=3:attack=10:release=200,' if aggressive else ''
    ffmpeg_cmd = [
        'ffmpeg', '-i', input_file,
        '-af', f'{compression}loudnorm=I={i_lufs}:LRA={lra}:TP={tp}',
        '-c:a', 'libmp3lame' if audio_format == 'mp3' else (f'lib{audio_format}' if audio_format != 'wav' else 'pcm_s16le'),
        '-b:a', bitrate,
        output_file
    ]
    try:
        print(f"Processing: {input_file}")
        subprocess.run(ffmpeg_cmd, check=True)
        print(f"✅ Saved: {output_file}")
    except subprocess.CalledProcessError as e:
        print(f"❌ Error processing {input_file}")
        print(e)


def process_directory(input_path, output_path, profile, aggressive, audio_format, bitrate):
    if not os.path.exists(output_path):
        os.makedirs(output_path)
    
    for input_file in os.listdir(input_path):
        full_input_path = os.path.join(input_path, input_file)
        if os.path.isfile(full_input_path):
            base_name = os.path.splitext(input_file)[0]
            output_file = os.path.join(output_path, f"{base_name}.{audio_format}")
            process_file(full_input_path, output_file, profile, aggressive, audio_format, bitrate)


def main():
    input_path = input("Enter the path to the input file or directory (leave blank for current directory): ").strip()
    if not input_path:
        input_path = os.getcwd()
    
    print("1. Broadcast TV\n2. Streaming Platforms\n3. Netflix\n4. YouTube\n5. AudioVault\n6. Custom")
    profile = input("Select loudness profile [Broadcast TV]: ").strip() or "1"
    
    aggressive = input("Apply aggressive compression? (y/n) [n]: ").strip().lower() == 'y'
    output_path = input("Enter the path for the output file or directory [output]: ").strip() or "output"
    
    print("1. AAC\n2. MP3\n3. EAC3\n4. WAV")
    audio_format = select_option("Select output format", FORMATS, "1")
    
    bitrate = input("Enter audio bitrate (e.g., 192k, 320k) [192k]: ").strip() or "192k"

    if os.path.isdir(input_path):
        print(f"🔄 Processing all files in directory: {input_path}")
        process_directory(input_path, output_path, profile, aggressive, audio_format, bitrate)
    else:
        base_name = os.path.splitext(os.path.basename(input_path))[0]
        output_file = os.path.join(output_path, f"{base_name}.{audio_format}")
        process_file(input_path, output_file, profile, aggressive, audio_format, bitrate)


if __name__ == "__main__":
    main()
