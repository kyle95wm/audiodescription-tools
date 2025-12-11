#!/bin/sh
# zip_logicx.sh — compress a Logic Pro .logicx project (no encryption)

if [ -z "$1" ]; then
  echo "Usage: $0 <project.logicx>"
  exit 1
fi

project="$1"
zipname="${project%/}.zip"

echo "Zipping: $project"
zip -r "$zipname" "$project"

# Verify integrity if possible
if command -v zip >/dev/null 2>&1 && zip -T "$zipname" >/dev/null 2>&1; then
  echo "✅  Zip verified successfully."
elif unzip -l "$zipname" >/dev/null 2>&1; then
  echo "✅  Basic structure verified."
else
  echo "⚠️  Verification failed. Check $zipname manually."
fi
