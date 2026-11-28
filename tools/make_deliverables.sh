#!/usr/bin/env bash
# Final deliverables (CI job "deliverables", run from the root of a QGC v5.1.5 checkout with this repo in ./mlgcs
# and ci_prepare.sh already applied).
#   usage: make_deliverables.sh <dist-dir with packages> <results-dir> <out-dir>
#     dist-dir:    MobilityLabGCS-x86_64.AppImage, MobilityLabGCS-installer-win64.exe, MobilityLabGCS-portable-win64.zip
#     results-dir: downloaded test artifacts (screens-*, windows-test)
set -euo pipefail
DIST="$(cd "$1" && pwd)"; RES="$(cd "$2" && pwd)"; mkdir -p "$3"; OUT="$(cd "$3" && pwd)"
VER="$(tr -d '[:space:]' < mlgcs/custom/ML_VERSION.txt)"
QGC_REF="$(git describe --tags 2>/dev/null || echo v5.1.5)"
N="MobilityLabGCS-$VER"
WORK="$(mktemp -d)"

# ---- 1-3. packages ----------------------------------------------------------------
cp "$DIST/MobilityLabGCS-installer-win64.exe" "$OUT/$N-Windows-Setup.exe"
cp "$DIST/MobilityLabGCS-portable-win64.zip"  "$OUT/$N-Windows-Portable.zip"
cp "$DIST/MobilityLabGCS-x86_64.AppImage"     "$OUT/$N-Ubuntu-x86_64.AppImage"

# ---- 4-5. no source archives from v1.2 on ---------------------------------------------
# Security review (docs/SECURITY_REVIEW.md): release files must not carry company source code (ACACT
# engine and the original ACACT Guard). Up to v1.1 a full source zip and a diff against QGC were
# attached; from v1.2 the release holds packages, documents, licences and checksums only.
# QGC is used under Apache-2.0; Qt is linked dynamically (LGPL-3.0, its libraries ship unmodified).

# ---- 6-11. documents -------------------------------------------------------------------
DOC="$WORK/$N-docs"
mkdir -p "$DOC/licenses"
python3 mlgcs/tools/test_report.py "$RES" "$DOC/TEST_RESULTS.md"
cp mlgcs/docs/BUILD.md mlgcs/docs/USER_MANUAL.md mlgcs/docs/ARCHITECTURE.md mlgcs/docs/STATUS.md mlgcs/docs/LICENSES.md "$DOC/"
cp mlgcs/CHANGELOG.md "$DOC/"
for f in SYSTEM_REQUIREMENTS INSTALL_UPDATE PERFORMANCE TECHNICAL_REPORT SECURITY_REVIEW; do
    [ -f "mlgcs/docs/$f.md" ] && cp "mlgcs/docs/$f.md" "$DOC/"
done
if [ -d mlgcs/docs/images ]; then mkdir -p "$DOC/images" && cp -r mlgcs/docs/images/. "$DOC/images/"; fi
cp LICENSE-APACHE "$DOC/licenses/QGroundControl-LICENSE-APACHE.txt" 2>/dev/null || true
cp LICENSE-GPL "$DOC/licenses/QGroundControl-LICENSE-GPL.txt" 2>/dev/null || true
cp mlgcs/custom/res/fonts/OFL-IBM-Plex.txt "$DOC/licenses/IBM-Plex-OFL.txt"
for l in lgpl-3.0 gpl-3.0 lgpl-2.1; do curl -fsSL "https://www.gnu.org/licenses/$l.txt" -o "$DOC/licenses/$l.txt" || true; done
printf 'MobilityLab GCS %s\nQGroundControl %s\nACACT Guard: 수정1 (rev1)\nPX4 (SITL tests) %s\nbuilt: %s, run %s, commit %s\n' \
    "$VER" "$QGC_REF" "${PX4_REF:-v1.16.2}" "$(date -u +%Y-%m-%dT%H:%MZ)" "$GITHUB_RUN_ID" "$(git -C mlgcs rev-parse HEAD)" > "$DOC/VERSION.txt"
(cd "$WORK" && zip -qr9 "$OUT/$N-docs.zip" "$N-docs")
cp "$DOC/TEST_RESULTS.md" "$OUT/$N-TEST_RESULTS.md"

(cd "$OUT" && sha256sum * > SHA256SUMS.txt)
ls -la "$OUT"
