#!/usr/bin/env python3

import pandas as pd
import argparse
import subprocess
import re

def get_frame_rate(video_file):
    """Get the frame rate of the video file using ffmpeg."""
    result = subprocess.run(
        ["ffprobe", "-v", "0", "-select_streams", "v", "-print_format", "flat", "-show_entries", "stream=r_frame_rate", video_file],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    )
    match = re.search(r'r_frame_rate="(\d+)/(\d+)"', result.stdout)
    if match:
        num, denom = match.groups()
        return float(num) / float(denom)
    else:
        raise ValueError("Could not determine frame rate.")

def smpte_to_srt(timecode, frame_rate):
    """Convert SMPTE timecode to SRT timecode."""
    parts = re.split(r'[:.]', timecode)
    if len(parts) != 4:
        raise ValueError(f"Invalid timecode format: {timecode}")
    
    hours, minutes, seconds, frames = map(int, parts)
    # Convert frames to milliseconds based on the provided frame rate
    milliseconds = int((frames / frame_rate) * 1000)
    return f"{hours:02}:{minutes:02}:{seconds:02},{milliseconds:03}"

def excel_to_srt(excel_file, srt_file, video_file):
    # Get the frame rate from the video file
    frame_rate = get_frame_rate(video_file)

    # Load the Excel file
    df = pd.read_excel(excel_file)
    
    # Open the SRT file for writing
    with open(srt_file, 'w') as file:
        for index, row in df.iterrows():
            line_number = row['Event Number']
            timecode_in = smpte_to_srt(row['TimeCode In'], frame_rate)
            timecode_out = smpte_to_srt(row['TimeCode Out'], frame_rate)
            script_text = row['Event']
            
            file.write(f"{line_number}\n")
            file.write(f"{timecode_in} --> {timecode_out}\n")
            file.write(f"{script_text}\n\n")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Convert Excel AD script to SRT file.')
    parser.add_argument('excel_file', help='Path to the Excel file')
    parser.add_argument('srt_file', help='Path to the output SRT file')
    parser.add_argument('video_file', help='Path to the video file to determine frame rate')
    args = parser.parse_args()

    excel_to_srt(args.excel_file, args.srt_file, args.video_file)