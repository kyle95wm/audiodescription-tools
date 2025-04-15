#!/usr/bin/env python3
import srt
import math
import sys
import os
from datetime import timedelta

def format_timestamp(ts):
    total_seconds = int(ts.total_seconds())
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60
    return f"{hours:02}:{minutes:02}:{seconds:02}"

def convert_srt_to_accessible_formats(input_file, plain_text=False, timecodes=False):
    if not os.path.exists(input_file):
        print(f"Error: File {input_file} not found.")
        return

    base_name = os.path.splitext(input_file)[0]
    output_txt = f"{base_name}.txt" if plain_text else None
    output_rtf = f"{base_name}.rtf" if not plain_text else None

    with open(input_file, 'r', encoding='utf-8') as file:
        subtitles = list(srt.parse(file.read()))

    # Write RTF output if plain_text is not selected
    if output_rtf:
        with open(output_rtf, 'w', encoding='utf-8') as rtf:
            rtf.write("{\\rtf1\\ansi\\deff0\\nouicompat\n")
            rtf.write("{\\fonttbl {\\f0\\fswiss Helvetica;}}\n")
            rtf.write("\\viewkind4\\uc1\n")
            rtf.write("\\pard\\sa200\\sl276\\slmult1\\f0\\fs22\n")

            for idx, subtitle in enumerate(subtitles, start=1):
                content = subtitle.content
                start = subtitle.start
                end = subtitle.end

                if content.startswith("["):
                    marker_end = content.find("]")
                    if marker_end != -1:
                        marker = content[:marker_end + 1]
                        content = f"{marker} {content[marker_end + 1:].strip()}"

                duration = end - start
                seconds = math.ceil(duration.total_seconds())

                rtf.write(f"Line {idx}: \\par\n")
                if timecodes:
                    rtf.write(f"IN: {format_timestamp(start)}\\par\n")
                    rtf.write(f"OUT: {format_timestamp(end)}\\par\n")
                rtf.write(f"{content}\\par\n")
                rtf.write(f"Duration: {seconds} seconds\\par\n")
                rtf.write("\\par\n")

            rtf.write("}")
        print(f"RTF script saved to {output_rtf}")

    # Write plain text output if requested
    if plain_text:
        with open(output_txt, 'w', encoding='utf-8', newline='\r\n') as txt:
            for idx, subtitle in enumerate(subtitles, start=1):
                content = subtitle.content
                start = subtitle.start
                end = subtitle.end

                if content.startswith("["):
                    marker_end = content.find("]")
                    if marker_end != -1:
                        marker = content[:marker_end + 1]
                        content = f"{marker} {content[marker_end + 1:].strip()}"

                duration = end - start
                seconds = math.ceil(duration.total_seconds())

                txt.write(f"Line {idx}:\n")
                if timecodes:
                    txt.write(f"IN: {format_timestamp(start)}\n")
                    txt.write(f"OUT: {format_timestamp(end)}\n")
                txt.write(f"{content}\n")
                txt.write(f"Duration: {seconds} seconds\n\n")

        print(f"Plain text script saved to {output_txt}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python script.py <input_file.srt> [--pt | --plain-text] [--tc | --timecodes]")
    else:
        input_file = sys.argv[1]
        plain_text_flag = "--pt" in sys.argv or "--plain-text" in sys.argv
        timecodes_flag = "--tc" in sys.argv or "--timecodes" in sys.argv
        convert_srt_to_accessible_formats(input_file, plain_text_flag, timecodes_flag)
