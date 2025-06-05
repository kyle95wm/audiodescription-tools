#!/usr/bin/env python3

"""
extract_wav_regions.py

This script extracts embedded cue/region metadata from a WAV file and reconstructs an SRT subtitle file.
It is useful in scenarios where:
- You’ve lost your original AD (audio description) script in SRT format
- You only have a WAV file with embedded markers/labels (e.g., exported from Logic Pro, Reaper, etc.)
- You want to recover approximate timings and text from embedded audio markers

How it works:
- Parses standard RIFF chunks in a WAV file to find:
  - 'cue ' chunk for marker sample offsets
  - 'labl' subchunks for cue text
  - 'ltxt' subchunks for region duration in samples (when present)
- Assumes a sample rate of 48,000 Hz (this can be changed)
- Generates an SRT with 2-second default durations if no region info is present

Limitations:
- Logic Pro only embeds cue points (not full regions), so durations are estimated
- Assumes embedded metadata follows the RIFF/adtl format (not iXML or BWF)

Output:
- Creates an SRT file with approximate timings and cue label text next to each marker
- Output file is named based on the WAV file, with '_reconstructed.srt' suffix

"""

import sys
import struct
import os

# Helper functions
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

def extract_metadata(filename):
    with open(filename, 'rb') as f:
        f.seek(12)  # Skip RIFF header
        cues = {}
        labels = {}
        regions = {}

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

    return cues, labels, regions

def generate_srt(cues, labels, regions, sample_rate=48000):
    entries = []
    for cue_id in sorted(cues, key=cues.get):
        start_sample = cues[cue_id]
        duration_samples = regions.get(cue_id, sample_rate * 2)  # default 2 sec if no region info
        end_sample = start_sample + duration_samples

        start_sec = start_sample / sample_rate
        end_sec = end_sample / sample_rate
        text = labels.get(cue_id, f"Cue {cue_id}")

        entries.append(f"{len(entries)+1}\n{format_time(start_sec)} --> {format_time(end_sec)}\n{text}\n\n")
    return ''.join(entries)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python extract_wav_regions.py input.wav")
        sys.exit(1)

    input_wav = sys.argv[1]
    cues, labels, regions = extract_metadata(input_wav)

    if not cues:
        print("No cue points found.")
        sys.exit(1)

    srt_output = generate_srt(cues, labels, regions)
    base = os.path.splitext(os.path.basename(input_wav))[0]
    output_path = f"{base}_reconstructed.srt"

    with open(output_path, "w", encoding="utf-8") as out_file:
        out_file.write(srt_output)

    print(f"✅ SRT file written to {output_path}")
