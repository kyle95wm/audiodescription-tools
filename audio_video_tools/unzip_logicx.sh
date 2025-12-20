#!/bin/sh
# unzip_logicx.sh — extract a zipped Logic Pro project

if [ -z "$1" ]; then
  echo "Usage: $0 <project.logicx.zip>"
  exit 1
fi

zipfile="$1"

# Remove the trailing .zip to form the folder name
outdir="${zipfile%.zip}"

echo "Extracting: $zipfile"
unzip "$zipfile" -d "$(dirname "$zipfile")"

if [ -d "$outdir" ]; then
  echo "✅  Extracted to: $outdir"
else
  echo "⚠️  Extraction may have failed. Check output manually."
fi
