#!/usr/bin/env python3

"""
extract_wav_regions.py

This script recovers region/cue/marker data from a WAV file and converts it into an SRT subtitle file.

It supports two metadata types:
1. RIFF chunks (`cue `, `labl`, `ltxt`) — from DAWs like Reaper or Logic Pro
2. FFmpeg-style chapters with `title` metadata — sometimes embedded on export

Use Cases:
- Rebuilding an AD script from a session WAV
- Recovering cue timing and narration lines
- Generating clean subtitle references

Output:
- Writes an SRT file as <input_filename>_reconstructed.srt

Dependencies:
- FFmpeg (`ffprobe`) must be installed
"""

import sys
import os
import struct
import subprocess
import json

def read_uint32(f):
    return struct.unpack('<I', f.read(4))[0]

def read_chunk_header(f):
    return f.read(4).decode('ascii', errors='ignore'), read_uint32(f)

def format_time(t):
    h = int(t // 3600)
    m = int((t % 3600) // 60)
    s = int(t % 60)
    ms = int((t - int(t)) * 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"

def extract_riff_metadata(filename):
    cues, labels, lengths = {}, {}, {}
    try:
        with open(filename, 'rb') as f:
            f.seek(12)  # skip RIFF header
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
                    list_type = f.read(4).decode('ascii', errors='ignore')
                    bytes_read = 4
                    if list_type == 'adtl':
                        while bytes_read < chunk_size:
                            sub_id = f.read(4).decode('ascii', errors='ignore')
                            sub_size = read_uint32(f)
                            sub_data = f.read(sub_size)
                            bytes_read += 8 + sub_size

                            if sub_id == 'labl':
                                cue_id = struct.unpack('<I', sub_data[:4])[0]
                                label = sub_data[4:].decode('utf-8', errors='ignore').rstrip('\x00')
                                labels[cue_id] = label

                            elif sub_id == 'ltxt':
                                cue_id = struct.unpack('<I', sub_data[:4])[0]
                                sample_length = struct.unpack('<I', sub_data[16:20])[0]
                                lengths[cue_id] = sample_length
                    else:
                        f.seek(chunk_size - 4, 1)
                else:
                    f.seek(chunk_size, 1)
    except Exception as e:
        return None
    return cues, labels, lengths

def generate_srt_from_riff(cues, labels, lengths, sample_rate=48000):
    entries = []
    cue_ids = sorted(cues, key=cues.get)
    for i, cue_id in enumerate(cue_ids):
        start = cues[cue_id] / sample_rate
        if cue_id in lengths:
            end = (cues[cue_id] + lengths[cue_id]) / sample_rate
        elif i + 1 < len(cue_ids):
            next_id = cue_ids[i + 1]
            end = cues[next_id] / sample_rate
        else:
            end = start + 2.0
        text = labels.get(cue_id, f"Cue {i+1}")
        entries.append(f"{i+1}\n{format_time(start)} --> {format_time(end)}\n{text}\n\n")
    return ''.join(entries)

def extract_ffmpeg_chapters(filename):
    cmd = ["ffprobe", "-loglevel", "error", "-print_format", "json", "-show_chapters", "-i", filename]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if not result.stdout:
        return ''
    data = json.loads(result.stdout)
    entries = []
    for i, ch in enumerate(data.get('chapters', []), 1):
        start = float(ch.get("start_time", 0))
        end = float(ch.get("end_time", start + 2))
        title = ch.get("tags", {}).get("title", f"Cue {i}")
        entries.append(f"{i}\n{format_time(start)} --> {format_time(end)}\n{title}\n\n")
    return ''.join(entries)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_wav_regions.py <input.wav>")
        sys.exit(1)

    filename = sys.argv[1]
    base = os.path.splitext(os.path.basename(filename))[0]
    output = f"{base}_reconstructed.srt"

    print("📦 Trying to extract embedded region/cue metadata...")
    riff = extract_riff_metadata(filename)
    if riff:
        cues, labels, lengths = riff
        if cues:
            print("✅ Found RIFF cue metadata. Generating SRT...")
            srt = generate_srt_from_riff(cues, labels, lengths)
            with open(output, "w", encoding="utf-8") as f:
                f.write(srt)
            print(f"✅ SRT file written to {output}")
            sys.exit(0)

    print("⚠️ No RIFF cue metadata found. Trying to extract FFmpeg-style chapters...")
    srt = extract_ffmpeg_chapters(filename)
    if srt:
        with open(output, "w", encoding="utf-8") as f:
            f.write(srt)
        print(f"✅ SRT file written to {output}")
    else:
        print("❌ No usable metadata found.")
