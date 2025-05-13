#!/usr/bin/env python3
import wave
import struct
import sys
import os
import argparse
from glob import glob

def time_to_seconds(time_str):
    hms, ms = time_str.strip().split(',')
    h, m, s = map(int, hms.split(':'))
    return h * 3600 + m * 60 + s + int(ms) / 1000

def time_to_sample(time_str, sample_rate):
    return int(time_to_seconds(time_str) * sample_rate)

def parse_srt(srt_path):
    with open(srt_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()

    regions = []
    i = 0
    while i < len(lines):
        if lines[i].strip().isdigit():
            start_end = lines[i+1].strip()
            start, end = start_end.split(' --> ')
            name = lines[i+2].strip() if (i + 2) < len(lines) else f'Region {i}'
            regions.append((start, end, name))
            i += 4
        else:
            i += 1
    return regions

def create_blank_audio(duration_seconds, sample_rate, bit_depth, channels):
    num_samples = int(duration_seconds * sample_rate)
    silent_frame = b'\x00' * (bit_depth // 8)
    return silent_frame * num_samples * channels

def add_region_markers(srt_path, output_path, sample_rate=48000, bit_depth=24, nchannels=1):
    sampwidth = bit_depth // 8
    regions = parse_srt(srt_path)

    if not regions:
        print(f"No regions found in {srt_path}. Skipping.")
        return

    last_end_time = max(time_to_seconds(end) for _, end, _ in regions)
    frames = create_blank_audio(last_end_time, sample_rate, bit_depth, nchannels)

    if len(frames) % 2 != 0:
        frames += b'\x00'

    cue_data = struct.pack('<I', len(regions))
    labl_chunks = b''
    ltxt_chunks = b''

    for idx, (start, end, name) in enumerate(regions, start=1):
        start_sample = time_to_sample(start, sample_rate)
        end_sample = time_to_sample(end, sample_rate)
        length = end_sample - start_sample

        cue_data += struct.pack('<I', idx)
        cue_data += struct.pack('<I', start_sample)
        cue_data += b'data'
        cue_data += struct.pack('<III', 0, 0, start_sample)

        label = name.encode('utf-8') + b'\x00'
        if len(label) % 2 != 0:
            label += b'\x00'
        labl_chunks += struct.pack('<4sI', b'labl', len(label) + 4)
        labl_chunks += struct.pack('<I', idx) + label

        ltxt_chunks += struct.pack('<4sI', b'ltxt', 20)
        ltxt_chunks += struct.pack('<I', idx)
        ltxt_chunks += struct.pack('<I', length)
        ltxt_chunks += struct.pack('<I', 0)
        ltxt_chunks += struct.pack('<H', 0) * 4

    cue_chunk = b'cue ' + struct.pack('<I', len(cue_data)) + cue_data
    adtl_data = labl_chunks + ltxt_chunks
    list_chunk = b'LIST' + struct.pack('<I', len(adtl_data) + 4) + b'adtl' + adtl_data

    riff_size = (
        (8 + 16) +               # fmt
        (8 + len(frames)) +      # data
        (8 + len(cue_chunk)) +   # cue
        (8 + len(list_chunk))    # LIST
    )

    with open(output_path, 'wb') as out_file:
        out_file.write(b'RIFF')
        out_file.write(struct.pack('<I', riff_size))
        out_file.write(b'WAVE')

        byte_rate = sample_rate * nchannels * sampwidth
        block_align = nchannels * sampwidth
        out_file.write(b'fmt ')
        out_file.write(struct.pack('<IHHIIHH',
                                   16, 1, nchannels, sample_rate,
                                   byte_rate, block_align, bit_depth))

        out_file.write(b'data')
        out_file.write(struct.pack('<I', len(frames)))
        out_file.write(frames)

        out_file.write(cue_chunk)
        out_file.write(list_chunk)

    print(f"✅ Created: {output_path}")

def batch_process(sample_rate, bit_depth, channels):
    srt_files = glob("*.srt")
    video_exts = [".mp4", ".mov", ".mkv"]

    for srt_file in srt_files:
        base = os.path.splitext(srt_file)[0]
        video_found = any(os.path.exists(base + ext) for ext in video_exts)
        if not video_found:
            print(f"⚠️  Skipping {srt_file}: no matching video file found.")
            continue

        output_wav = base + '_regions.wav'
        add_region_markers(srt_file, output_wav, sample_rate, bit_depth, channels)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate a blank WAV file with region markers from SRTs.')
    parser.add_argument('srt_path', nargs='?', help='Path to the SRT file (single file mode)')
    parser.add_argument('--rate', type=int, default=48000, help='Sample rate in Hz (default: 48000)')
    parser.add_argument('--bitdepth', type=int, default=24, help='Bit depth (default: 24)')
    parser.add_argument('--channels', type=int, default=1, help='Number of audio channels (default: 1)')
    parser.add_argument('--batch', action='store_true', help='Batch mode: process all matching SRT + video file pairs')

    args = parser.parse_args()

    if args.batch:
        batch_process(args.rate, args.bitdepth, args.channels)
    elif args.srt_path:
        output_wav = os.path.splitext(args.srt_path)[0] + '_regions.wav'
        add_region_markers(args.srt_path, output_wav, args.rate, args.bitdepth, args.channels)
    else:
        print("❌ Error: Please provide an SRT file or use --batch")
        sys.exit(1)
