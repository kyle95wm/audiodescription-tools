# AudioVault Mastering Tool

This script prepares audio description tracks for delivery to AudioVault. It handles compression, loudness normalization, and automatically adds intro and outro bumpers to meet AudioVault Original (AVO) standards.

## Features

- Targets AudioVault loudness: **-16.3 LUFS**, **-2.6 dBTP**, **LRA 5**
- Converts input WAV to stereo **MP3 at 192kbps**
- Adds bumpers and spacing automatically
- Supports single input/output file processing

## Usage

```bash
./master_av.py input.wav output.mp3
```

## Bumper Layout

The final mastered MP3 will be structured as follows:

```
[avo_head.mp3] > [main content] > [1 sec silence] > [avo_tail.mp3] > [1 sec silence]
```

- `avo_head.mp3` is the short "An AudioVault Original" bumper, with baked-in silence.
- `avo_tail.mp3` is the longer disclaimer-style bumper.
- Silence is automatically inserted at the end if `silence_1s.mp3` is missing.

## Required Assets

Place the following in `~/audio-vault-assets/`:

- `avo_head.mp3` — short bumper with ~1s silence baked in
- `avo_tail.mp3` — long disclaimer bumper
- `silence_1s.mp3` — optional; auto-generated if missing

## Trimming the Bumper (Optional)

If you need to remove the intro bumper (e.g. to sync the audio track with video), use FFmpeg:

```bash
# Trim off the first 3 seconds
ffmpeg -y -ss 3 -i input.mp3 -c copy output_trimmed.mp3
```

## Notes

- If you're using `DescribeAlign`, it will automatically offset the video start to match the bumper.
- All output files are forced to 48kHz stereo CBR to ensure consistency.
