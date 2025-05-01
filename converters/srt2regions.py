import wave
import struct
import sys
import os
import argparse

# Convert SRT timestamp string to total seconds
def time_to_seconds(time_str):
    hms, ms = time_str.strip().split(',')
    h, m, s = map(int, hms.split(':'))
    return h * 3600 + m * 60 + s + int(ms) / 1000

# Convert timestamp string to sample index using the given sample rate
def time_to_sample(time_str, sample_rate):
    return int(time_to_seconds(time_str) * sample_rate)

# Parse the SRT file and extract a list of (start, end, label) tuples
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

# Generate silent PCM audio data for the given duration
def create_blank_audio(duration_seconds, sample_rate, bit_depth, channels):
    num_samples = int(duration_seconds * sample_rate)
    silent_frame = b'\x00' * (bit_depth // 8)
    return silent_frame * num_samples * channels

# Generate WAV file with embedded region markers based on SRT cues
def add_region_markers(srt_path, output_path, sample_rate=48000, bit_depth=24, nchannels=1):
    sampwidth = bit_depth // 8
    regions = parse_srt(srt_path)

    if not regions:
        print("No regions found in SRT.")
        return

    # Determine how long the WAV needs to be (based on last cue end time)
    last_end_time = max(time_to_seconds(end) for _, end, _ in regions)
    frames = create_blank_audio(last_end_time, sample_rate, bit_depth, nchannels)

    cue_data = struct.pack('<I', len(regions))  # Number of cue points
    labl_chunks = b''  # Label chunk data
    ltxt_chunks = b''  # Region duration data

    for idx, (start, end, name) in enumerate(regions, start=1):
        start_sample = time_to_sample(start, sample_rate)
        end_sample = time_to_sample(end, sample_rate)
        length = end_sample - start_sample

        # Cue point chunk (cue )
        cue_data += struct.pack('<I', idx)                   # Cue ID
        cue_data += struct.pack('<I', start_sample)          # Sample offset
        cue_data += b'data'                                  # Chunk ID
        cue_data += struct.pack('<III', 0, 0, start_sample)  # Reserved values + position

        # Label chunk (labl)
        label = name.encode('utf-8') + b'\x00'
        label_size = len(label)
        pad = b'\x00' if label_size % 2 != 0 else b''
        labl_chunks += struct.pack('<4sI', b'labl', label_size + 4)
        labl_chunks += struct.pack('<I', idx) + label + pad

        # Region length chunk (ltxt)
        ltxt_chunks += struct.pack('<4sI', b'ltxt', 20)
        ltxt_chunks += struct.pack('<I', idx)
        ltxt_chunks += struct.pack('<I', length)
        ltxt_chunks += struct.pack('<I', 0)          # Purpose ID (not used)
        ltxt_chunks += struct.pack('<H', 0) * 4      # Country, language, dialect, code page

    # Combine cue, labl, ltxt chunks
    cue_chunk = b'cue ' + struct.pack('<I', len(cue_data)) + cue_data
    adtl_data = labl_chunks + ltxt_chunks
    list_chunk = b'LIST' + struct.pack('<I', len(adtl_data) + 4) + b'adtl' + adtl_data

    # Write the final WAV file with all chunks
    with open(output_path, 'wb') as out_file:
        out_file.write(b'RIFF')
        total_size = 4 + (8 + 16) + (8 + len(frames)) + (8 + len(cue_chunk)) + (8 + len(list_chunk))
        out_file.write(struct.pack('<I', total_size))
        out_file.write(b'WAVE')

        # fmt chunk (standard PCM format)
        byte_rate = sample_rate * nchannels * sampwidth
        block_align = nchannels * sampwidth
        out_file.write(b'fmt ')
        out_file.write(struct.pack('<IHHIIHH',
                                   16, 1, nchannels, sample_rate,
                                   byte_rate, block_align, bit_depth))

        # data chunk (silent audio)
        out_file.write(b'data')
        out_file.write(struct.pack('<I', len(frames)))
        out_file.write(frames)

        # cue and LIST (marker data)
        out_file.write(cue_chunk)
        out_file.write(list_chunk)

    print(f'Done! Region-marked WAV saved to: {output_path}')

# Command-line interface
if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Generate a blank WAV file with region markers from an SRT file.')
    parser.add_argument('srt_path', help='Path to the SRT file')
    parser.add_argument('--rate', type=int, default=48000, help='Sample rate in Hz (default: 48000)')
    parser.add_argument('--bitdepth', type=int, default=24, help='Bit depth (default: 24)')
    parser.add_argument('--channels', type=int, default=1, help='Number of audio channels (default: 1)')

    args = parser.parse_args()
    output_wav = os.path.splitext(args.srt_path)[0] + '_regions.wav'
    add_region_markers(args.srt_path, output_wav, args.rate, args.bitdepth, args.channels)
