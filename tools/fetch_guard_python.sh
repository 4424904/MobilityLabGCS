#!/usr/bin/env bash
# Windows CI: a private Python for the ACACT guard, bundled into the installer
# (<install>/bin/python). No Python install is needed on the operator PC.
#   - python.org embeddable package (3.12, amd64)
#   - mavsdk<4 (includes mavsdk_server.exe), numpy — Windows wheels only
set -euo pipefail
DEST="${1:?destination folder}"
PYVER=3.12.10
mkdir -p "$DEST"
curl -fsSL --retry 3 -o /tmp/pyembed.zip "https://www.python.org/ftp/python/${PYVER}/python-${PYVER}-embed-amd64.zip"
unzip -q -o /tmp/pyembed.zip -d "$DEST"
# The ._pth file puts embedded Python in isolated mode, which also drops the
# script's own folder from sys.path (guard.py imports config, core, …). Remove
# it: python312.zip next to python.exe still provides the standard library,
# and site adds Lib/site-packages.
rm -f "$DEST"/python*._pth
python -m pip install -q --disable-pip-version-check \
    --target "$DEST/Lib/site-packages" \
    --platform win_amd64 --python-version 3.12 --implementation cp --only-binary=:all: \
    "mavsdk<4" numpy
ls "$DEST" | head -30
du -sh "$DEST"
