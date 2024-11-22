#!/usr/bin/env python3
import srt
import math
import sys
import os

def convert_srt_to_accessible_formats(input_file, plain_text=False):
    # Check if input file exists
    if not os.path.exists(input_file):
        print(f"Error: File {input_file} not found.")
        return

    # Derive output file names
    base_name = os.path.splitext(input_file)[0]
    output_rtf = f"{base_name}.rtf"
    output_txt = f"{base_name}.txt" if plain_text else None

    # Read the SRT file
    with open(input_file, 'r', encoding='utf-8') as file:
        subtitles = list(srt.parse(file.read()))

    # Write RTF output
    with open(output_rtf, 'w', encoding='utf-8') as rtf:
        # RTF header
        rtf.write("{\\rtf1\\ansi\\deff0\\nouicompat\n")
        rtf.write("{\\fonttbl {\\f0\\fswiss Helvetica;}}\n")
        rtf.write("\\viewkind4\\uc1\n")
        rtf.write("\\pard\\sa200\\sl276\\slmult1\\f0\\fs22\n")

        for idx, subtitle in enumerate(subtitles, start=1):
            content = subtitle.content
            start = subtitle.start
            end = subtitle.end

            # Highlight markers (e.g., [FAST], [Step])
            if content.startswith("["):
                marker_end = content.find("]")
                if marker_end != -1:
                    marker = content[:marker_end + 1]
                    content = f"{marker} {content[marker_end + 1:].strip()}"

            # Calculate estimated duration
            duration = end - start
            seconds = math.ceil(duration.total_seconds())

            # Write to RTF
            rtf.write(f"Line {idx}: \\par\n")
            rtf.write(f"{content}\\par\n")
            rtf.write(f"Duration: {seconds} seconds\\par\n")
            rtf.write("\\par\n")  # Add spacing between entries

        rtf.write("}")

    print(f"RTF script saved to {output_rtf}")

    # Write plain text output if needed
    if plain_text:
        with open(output_txt, 'w', encoding='utf-8') as txt:
            for idx, subtitle in enumerate(subtitles, start=1):
                content = subtitle.content
                start = subtitle.start
                end = subtitle.end

                # Highlight markers
                if content.startswith("["):
                    marker_end = content.find("]")
                    if marker_end != -1:
                        marker = content[:marker_end + 1]
                        content = f"{marker} {content[marker_end + 1:].strip()}"

                # Calculate estimated duration
                duration = end - start
                seconds = math.ceil(duration.total_seconds())

                # Write to plain text
                txt.write(f"Line {idx}:\n")
                txt.write(f"{content}\n")
                txt.write(f"Duration: {seconds} seconds\n\n")  # Add an extra line for spacing

        print(f"Plain text script saved to {output_txt}")

if __name__ == "__main__":
    # Check for proper arguments
    if len(sys.argv) < 2:
        print("Usage: python script.py <input_file.srt> [--pt | --plain-text]")
    else:
        input_file = sys.argv[1]
        plain_text_flag = "--pt" in sys.argv or "--plain-text" in sys.argv
        convert_srt_to_accessible_formats(input_file, plain_text_flag)
