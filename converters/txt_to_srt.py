#!/usr/bin/env python3
import re
import sys
import os
from datetime import timedelta
import srt

def parse_timecode(tc):
    try:
        h, m, s = map(int, tc.split(":"))
        return timedelta(hours=h, minutes=m, seconds=s)
    except ValueError:
        print(f"Error: Invalid timecode format '{tc}'. Use hh:mm:ss")
        sys.exit(1)

def process_txt_to_srt(input_file):
    if not os.path.exists(input_file):
        print(f"Error: File {input_file} not found.")
        return

    base_name = os.path.splitext(input_file)[0]
    output_srt = f"{base_name}.srt"

    with open(input_file, 'r', encoding='utf-8') as file:
        lines = file.readlines()

    srt_entries = []
    idx = 1
    current_entry = {}
    for line in lines:
        line = line.strip()
        
        if line.startswith("IN:"):
            current_entry['start'] = parse_timecode(line.split("IN: ")[1])
        elif line.startswith("OUT:"):
            current_entry['end'] = parse_timecode(line.split("OUT: ")[1])
        elif line.startswith("Line"):
            continue
        elif line.startswith("Duration:"):
            if 'start' in current_entry and 'end' in current_entry and 'content' in current_entry:
                srt_entries.append(
                    srt.Subtitle(
                        index=idx,
                        start=current_entry['start'],
                        end=current_entry['end'],
                        content=current_entry['content']
                    )
                )
                idx += 1
                current_entry = {}
        elif line:
            current_entry['content'] = line

    srt_output = srt.compose(srt_entries)

    with open(output_srt, 'w', encoding='utf-8') as srt_file:
        srt_file.write(srt_output)

    print(f"SRT file saved to {output_srt}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python txt_to_srt.py <input_file.txt>")
    else:
        input_file = sys.argv[1]
        process_txt_to_srt(input_file)
