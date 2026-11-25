#!/usr/bin/env bash
# Run from the root of a QGroundControl checkout that has this repo checked out in ./mlgcs.
# Copies the MobilityLab plugin in as ./custom and applies the small core patches.
set -euo pipefail

rm -rf custom
cp -r mlgcs/custom custom

shopt -s nullglob
for p in mlgcs/patches/*.patch; do
    echo "Applying $p"
    git apply --whitespace=nowarn "$p"
done

# Korean UI: fill strings QGC's Korean translation still has in English
PY=$(command -v python3 || command -v python)
"$PY" mlgcs/tools/apply_ko.py mlgcs/custom/i18n/ko_overrides.json

echo "MobilityLab customisation applied:"
find custom -maxdepth 2 | sort
