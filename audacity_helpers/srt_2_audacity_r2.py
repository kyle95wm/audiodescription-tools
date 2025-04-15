import sys
import re

if len(sys.argv) != 3:
    print("Usage: python3 2audacity.py <inputfile.srt> <outputfile.txt>")
    sys.exit(1)

inputfile = sys.argv[1]
outputfile = sys.argv[2]

counter = 1
pattern = re.compile(r'(\d{2}):(\d{2}):(\d{2}),(\d{3}) --> (\d{2}):(\d{2}):(\d{2}),(\d{3})')

def convert_to_seconds(hours, minutes, seconds, milliseconds):
    return hours * 3600 + minutes * 60 + seconds + milliseconds / 1000.0

with open(inputfile, 'r') as infile, open(outputfile, 'w') as outfile:
    fields = None
    for line in infile:
        line = line.strip()
        match = pattern.match(line)
        if match:
            fields = match.groups()
            start = convert_to_seconds(int(fields[0]), int(fields[1]), int(fields[2]), int(fields[3]))
            end = convert_to_seconds(int(fields[4]), int(fields[5]), int(fields[6]), int(fields[7]))
            fields = [f"{start:.6f}", f"{end:.6f}", '']
        elif line.isdigit():
            counter = int(line)
        elif line:
            if fields is None:
                fields = ['', '', '']
            fields[2] += ' ' + line
        else:
            if fields is not None:
                printline = f"{fields[0]}\t{fields[1]}\t{str(counter)} {fields[2][:15]}\n"
                outfile.write(printline)
                counter += 1
                fields = None

print("Conversion complete. Output saved to", outputfile)