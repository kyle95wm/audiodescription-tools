#!/usr/bin/env python3

"""
extract_wav_regions.py

This script recovers region/cue/marker data from a WAV file and converts it into an SRT subtitle file.

It supports two metadata types:
1. **RIFF chunks** (`cue `, `labl`, `ltxt`) — traditional markers embedded by Reaper, Logic Pro, etc.
2. **FFmpeg-style chapters** with `title` metadata — often added by DAWs like Reaper when exporting chapter markers.

Use Cases:
- Rebuilding an AD script based on a session WAV with embedded markers
- Recovering cue timing and text when the original script is lost
- Extracting clean SRT files for reference or editing

Output:
- An SRT file saved as `<input_filename>_reconstructed.srt`

Dependencies:
- FFmpeg must be installed and accessible via `ffprobe`
"""

import sys
import os
import struct
import subprocess
import json

def read_uint32(f):
    return struct.unpack('<I', f.read(4))[0]

def read_chunk_header(f):
    return f.read(4).decode('ascii'), read_uint32(f)

def format_time(t):
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = int(t % 60)
    ms = int((t - int(t)) * 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"

def extract_riiff_metadata(filename):
    cues, labels, regions = {}, {}, {}
    try:
        with open(filename, 'rb') as f:
            f.seek(12)
            while True:
                try:
                    chunk_id, chunk_size = read_chunk_header(f)
                except:
                    break

                if chunk_id == 'cue ':
                    num_cues = read_uint32(f)
                    for _ in range(num_cues):
                        cue_data = f.read(24)
                        cue_id, _, _, _, _, sample_offset = struct.unpack('<IIIIII', cue_data)
                        cues[cue_id] = sample_offset

                elif chunk_id == 'LIST':
                    list_type = f.read(4).decode('ascii')
                    bytes_read = 4
                    if list_type == 'adtl':
                        while bytes_read < chunk_size:
                            subchunk_id = f.read(4).decode('ascii')
                            subchunk_size = read_uint32(f)
                            subchunk_data = f.read(subchunk_size)
                            bytes_read += 8 + subchunk_size

                            if subchunk_id == 'labl':
                                cue_point_id = struct.unpack('<I', subchunk_data[:4])[0]
                                label_text = subchunk_data[4:].decode('utf-8', errors='ignore').rstrip('\x00')
                                labels[cue_point_id] = label_text

                            elif subchunk_id == 'ltxt':
                                cue_point_id, _, _, sample_length, _ = struct.unpack('<IIIII', subchunk_data[:20])
                                regions[cue_point_id] = sample_length
                    else:
                        f.seek(chunk_size - 4, 1)
                else:
                    f.seek(chunk_size, 1)
    except:
        return None
    return cues, labels, regions

def generate_srt_from_riiff(cues, labels, regions, sample_rate=48000):
    entries = []
    for cue_id in sorted(cues, key=cues.get):
        start_sample = cues[cue_id]
        duration_samples = regions.get(cue_id, sample_rate * 2)
        end_sample = start_sample + duration_samples
        start_sec = start_sample / sample_rate
        end_sec = end_sample / sample_rate
        text = labels.get(cue_id, f"Cue {cue_id}")
        entries.append(f"{len(entries)+1}\n{format_time(start_sec)} --> {format_time(end_sec)}\n{text}\n\n")
    return ''.join(entries)

def extract_chapters_with_ffmpeg(filename):
    cmd = ["ffprobe", "-loglevel", "error", "-print_format", "json", "-show_chapters", "-i", filename]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    chapters_json = json.loads(result.stdout)
    entries = []
    for i, chapter in enumerate(chapters_json.get("chapters", []), start=1):
        start = float(chapter['start_time'])
        end = float(chapter['end_time'])
        title = chapter.get("tags", {}).get("title", f"Cue {i}")
        entries.append(f"{i}\n{format_time(start)} --> {format_time(end)}\n{title}\n\n")
    return ''.join(entries)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_wav_regions.py input.wav")
        sys.exit(1)

    input_wav = sys.argv[1]
    base = os.path.splitext(os.path.basename(input_wav))[0]
    output_path = f"{base}_reconstructed.srt"

    print("📦 Trying to extract embedded region/cue metadata...")
    result = extract_riiff_metadata(input_wav)

    if result:
        cues, labels, regions = result
        if cues:
            print("✅ Found RIFF cue metadata. Generating SRT...")
            srt_output = generate_srt_from_riiff(cues, labels, regions)
            with open(output_path, "w", encoding="utf-8") as out_file:
                out_file.write(srt_output)
            print(f"✅ SRT file written to {output_path}")
            sys.exit(0)

    print("⚠️ No RIFF cue metadata found. Trying to extract FFmpeg-style chapters...")
    try:
        srt_output = extract_chapters_with_ffmpeg(input_wav)
        if srt_output:
            with open(output_path, "w", encoding="utf-8") as out_file:
                out_file.write(srt_output)
            print(f"✅ SRT file written to {output_path}")
        else:
            print("❌ No usable chapter metadata found either.")
    except Exception as e:
        print(f"❌ Error during chapter extraction: {e}")
