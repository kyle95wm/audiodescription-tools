#!/usr/bin/env python3
import os
import argparse
import subprocess

SUPPORTED_FORMATS = ['.mp4', '.mkv', '.wav', '.mp3', '.aac', '.eac3']

def process_file(input_file, output_file, profile, aggressive_compression, audio_format, bitrate):
    audio_temp = "temp_audio." + audio_format
    final_output = output_file if output_file.endswith(".mp4") else output_file + ".mp4"
    
    # Extract audio from video
    extract_audio_cmd = [
        "ffmpeg", "-i", input_file, "-vn", "-acodec", "copy", audio_temp
    ]
    
    # Process extracted audio
    ffmpeg_cmd = [
        "ffmpeg",
        "-i", audio_temp,
        "-af", f"acompressor=threshold=-18dB:ratio=3:attack=10:release=200,loudnorm=I={profile['LUFS']}:LRA={profile['LRA']}:TP={profile['TP']}"
    ]
    
    # Aggressive compression option
    if aggressive_compression:
        ffmpeg_cmd[3] = f"acompressor=threshold=-24dB:ratio=4:attack=5:release=150,{ffmpeg_cmd[3]}"
    
    # Audio codec/format handling
    if audio_format == "aac":
        ffmpeg_cmd += ["-c:a", "aac", "-b:a", bitrate]
    elif audio_format == "eac3":
        ffmpeg_cmd += ["-c:a", "eac3", "-b:a", bitrate]
    elif audio_format == "mp3":
        ffmpeg_cmd += ["-c:a", "libmp3lame", "-q:a", "2"]
    elif audio_format == "wav":
        ffmpeg_cmd += ["-c:a", "pcm_s16le"]
    else:
        raise ValueError(f"Unsupported audio format: {audio_format}")
    
    ffmpeg_cmd += ["processed_audio." + audio_format]
    
    # Mux processed audio back into video
    mux_cmd = [
        "ffmpeg", "-i", input_file,
        "-i", "processed_audio." + audio_format,
        "-c:v", "copy",  # Keep the original video stream
        "-map", "0:v:0",  # Map video from input
        "-map", "1:a:0",  # Map audio from processed file
        final_output
    ]
    
    try:
        # Step 1: Extract audio
        subprocess.run(extract_audio_cmd, check=True)
        print("✅ Audio extracted successfully.")
        
        # Step 2: Process extracted audio
        subprocess.run(ffmpeg_cmd, check=True)
        print("✅ Audio processed successfully.")
        
        # Step 3: Remux audio and video
        subprocess.run(mux_cmd, check=True)
        print(f"✅ New video with processed audio saved as: {final_output}")
        
        # Cleanup
        os.remove(audio_temp)
        os.remove("processed_audio." + audio_format)
        
    except subprocess.CalledProcessError as e:
        print("❌ Error during processing.")
        print(e)

def main():
    parser = argparse.ArgumentParser(description="Video Mastering Script with Audio Processing")
    parser.add_argument("input", help="Input video file")
    parser.add_argument("output", help="Output video file")
    parser.add_argument("--profile", type=str, default="Broadcast TV",
                        choices=["Broadcast TV", "Streaming Platforms", "Netflix", "YouTube", "AudioVault", "Custom"],
                        help="Loudness profile")
    parser.add_argument("--format", type=str, default="aac", choices=["aac", "mp3", "eac3", "wav"], help="Output audio format")
    parser.add_argument("--bitrate", type=str, default="192k", help="Audio bitrate (e.g., 192k, 320k)")
    parser.add_argument("--aggressive", action="store_true", help="Apply aggressive compression")
    args = parser.parse_args()

    profiles = {
        "Broadcast TV": {"LUFS": -24, "TP": -2, "LRA": 6},
        "Streaming Platforms": {"LUFS": -16, "TP": -1, "LRA": 6},
        "Netflix": {"LUFS": -27, "TP": -2, "LRA": 10},
        "YouTube": {"LUFS": -14, "TP": -1, "LRA": 8},
        "AudioVault": {"LUFS": -16.3, "TP": -2.6, "LRA": 5},
    }

    # Custom profile input
    if args.profile == "Custom":
        lufs = float(input("Enter target LUFS: "))
        tp = float(input("Enter true peak (dBTP): "))
        lra = float(input("Enter loudness range (LRA): "))
        profiles["Custom"] = {"LUFS": lufs, "TP": tp, "LRA": lra}

    process_file(args.input, args.output, profiles[args.profile], args.aggressive, args.format, args.bitrate)

if __name__ == "__main__":
    main()
