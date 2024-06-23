#!/usr/bin/env python3

import pandas as pd
import re
import argparse
from datetime import timedelta
import openpyxl
from openpyxl.utils.dataframe import dataframe_to_rows
import os

def srt_to_smpte(timecode, frame_rate):
    """Convert SRT timecode to SMPTE timecode."""
    hours, minutes, seconds, milliseconds = map(int, re.split('[:,]', timecode))
    total_seconds = timedelta(hours=hours, minutes=minutes, seconds=seconds, milliseconds=milliseconds).total_seconds()
    frames = int((total_seconds * frame_rate) % frame_rate)
    return f"{hours:02}:{minutes:02}:{seconds:02}:{frames:02}"

def parse_srt(srt_file, frame_rate):
    with open(srt_file, 'r') as file:
        content = file.read()
    
    pattern = re.compile(r'(\d+)\n(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\n(.*?)\n\n', re.DOTALL)
    matches = pattern.findall(content)

    data = []
    for match in matches:
        line_number = int(match[0])
        timecode_in = srt_to_smpte(match[1], frame_rate)
        timecode_out = srt_to_smpte(match[2], frame_rate)
        script_text = match[3].replace('\n', ' ')
        data.append([line_number, timecode_in, timecode_out, script_text])

    return data

def srt_to_excel(srt_file, excel_file, frame_rate, template_file=None):
    data = parse_srt(srt_file, frame_rate)
    df = pd.DataFrame(data, columns=['Line Number', 'Timecode In', 'Timecode Out', 'Script (en)'])
    
    if not excel_file.endswith('.xlsx'):
        excel_file += '.xlsx'

    if template_file:
        wb = openpyxl.load_workbook(template_file)
        ws = wb.active

        # Start writing data from the second row
        for r_idx, row in enumerate(dataframe_to_rows(df, index=False, header=False), 2):
            for c_idx, value in enumerate(row, 1):
                ws.cell(row=r_idx, column=c_idx, value=value)
        
        wb.save(excel_file)
    else:
        with pd.ExcelWriter(excel_file, engine='openpyxl') as writer:
            df.to_excel(writer, index=False, startrow=1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Convert SRT file to Excel AD script.')
    parser.add_argument('srt_file', help='Path to the SRT file')
    parser.add_argument('excel_file', help='Path to the output Excel file')
    parser.add_argument('frame_rate', type=float, help='Frame rate of the video (e.g., 23.976, 24, 25, 30)')
    parser.add_argument('--template', help='Path to the Excel template file', default=None)
    args = parser.parse_args()

    srt_to_excel(args.srt_file, args.excel_file, args.frame_rate, args.template)