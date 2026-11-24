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

echo "MobilityLab customisation applied:"
find custom -maxdepth 2 | sort
