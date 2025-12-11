import sys
import xml.etree.ElementTree as ET

def usf_to_srt(usf_file):
    srt_file = usf_file.rsplit('.', 1)[0] + '.srt'
    tree = ET.parse(usf_file)
    subs = tree.findall('.//subtitle')

    with open(srt_file, 'w', encoding='utf-8') as f:
        for i, s in enumerate(subs, 1):
            start = s.get('start').replace('.', ',')
            stop = s.get('stop').replace('.', ',')
            text = ''.join(t.text or '' for t in s.findall('.//text')).strip()
            f.write(f'{i}\n{start} --> {stop}\n{text}\n\n')
    print(f'Converted to {srt_file}')

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python convert_usf.py <filename.usf>')
    else:
        usf_to_srt(sys.argv[1])
