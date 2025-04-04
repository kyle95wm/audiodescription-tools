#!/usr/bin/env python3

import re
import argparse
from pathlib import Path

def to_seconds(tc):
    h, m, s_ms = tc.split(":")
    s, ms = s_ms.split(",")
    return int(h) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000

def srt_to_markers(srt_path):
    with open(srt_path, "r", encoding="utf-8") as f:
        srt_data = f.read()

    pattern = re.compile(
        r"(\d+)\s+(\d{2}:\d{2}:\d{2},\d{3}) --> (\d{2}:\d{2}:\d{2},\d{3})\s+(.*?)\s*(?=\n\d+\n|\Z)",
        re.DOTALL,
    )
    matches = pattern.findall(srt_data)

    marker_lines = []
    for idx, (num, start_tc, end_tc, text) in enumerate(matches, start=1):
        start_sec = to_seconds(start_tc)
        end_sec = to_seconds(end_tc)
        text_clean = text.replace("\n", " ").strip().replace('"', "'")

        guid = "{{{:08X}-{:04X}-{:04X}-{:04X}-{:012X}}}".format(
            idx, idx, idx, idx, idx  # placeholder GUIDs
        )
        marker_lines.append(f'  MARKER {idx} {start_sec:.2f} "{text_clean}" 1 0 1 B {guid} 0')
        marker_lines.append(f'  MARKER {idx} {end_sec:.2f} "" 1')
    return marker_lines

def inject_markers_into_rpp(template_path, marker_lines, output_path):
    with open(template_path, "r", encoding="utf-8") as f:
        rpp_base = f.read()

    insert_at = rpp_base.rfind(">")
    rpp_with_markers = rpp_base[:insert_at] + "\n" + "\n".join(marker_lines) + "\n" + rpp_base[insert_at:]

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(rpp_with_markers)

def main():
    parser = argparse.ArgumentParser(description="Inject SRT cues into a Reaper .rpp project as markers.")
    parser.add_argument("srt_file", help="Path to the SRT file")
    parser.add_argument("template_rpp", help="Path to the base Reaper .rpp file")
    parser.add_argument("output_rpp", help="Path to save the new .rpp file with markers")

    args = parser.parse_args()

    marker_lines = srt_to_markers(Path(args.srt_file))
    inject_markers_into_rpp(Path(args.template_rpp), marker_lines, Path(args.output_rpp))
    print(f"Done! Created: {args.output_rpp}")

if __name__ == "__main__":
    main()
