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

# ---- 4. full source (no .git, build output, caches or binaries) ----------------------
SRC="$WORK/$N-source"
mkdir -p "$SRC"
rsync -a --exclude '.git' --exclude 'mlgcs' --exclude 'build' ./ "$SRC/"
(cd mlgcs && git archive --format=tar --prefix=mobilitylab/ HEAD) | tar -x -C "$SRC"
cat > "$SRC/BUILD_INFO.md" <<EOF
# MobilityLab GCS $VER — source

* QGroundControl $QGC_REF (unchanged except the MobilityLab patches below), with the MobilityLab plugin in \`custom/\`
* MobilityLab repository (tools, docs, original ACACT sources, CI) in \`mobilitylab/\` at commit $(git -C mlgcs rev-parse --short HEAD)
* Patches already applied: $(ls mlgcs/patches | tr '\n' ' ')
* Build: see mobilitylab/docs/BUILD.md. Third-party C/C++ dependencies are fetched by CMake (CPM) at configure time,
  versions pinned by QGC $QGC_REF (cmake/), Qt 6.10 (.github/actions/build-setup).
* Built from this tree by GitHub Actions run $GITHUB_RUN_ID.
EOF
find "$SRC" \( -name '*.exe' -o -name '*.AppImage' -o -name '*.o' -o -name '*.so' -o -name '*.dll' -o -name '__pycache__' -o -name '.ccache' \) -prune -exec rm -rf {} + 2>/dev/null || true
(cd "$WORK" && zip -qr9 "$OUT/$N-source.zip" "$N-source")

# ---- 5. what changed against QGC -------------------------------------------------------
CH="$WORK/$N-changes-vs-QGC-$QGC_REF"
mkdir -p "$CH"
git add -A -N . ':!mlgcs' 2>/dev/null || true
git diff --stat -- . ':!mlgcs' > "$CH/CHANGED_FILES.txt"
git diff -- . ':!mlgcs' > "$CH/qgc-$QGC_REF-to-mobilitylab.diff"
cp -r mlgcs/custom mlgcs/patches "$CH/"
mkdir -p "$CH/tools" && cp mlgcs/tools/ci_prepare.sh mlgcs/tools/patch_installer.py mlgcs/tools/apply_ko.py "$CH/tools/"
cat > "$CH/README.md" <<EOF
# Changes against QGroundControl $QGC_REF

* \`custom/\` — the MobilityLab plugin (all new code: ACACT engine and runtime, UI, analysis, i18n)
* \`patches/\` — the only edits to QGC source files (see CHANGED_FILES.txt)
* \`tools/ci_prepare.sh\` applies both to a clean QGC checkout; \`patch_installer.py\` edits the Windows installer script,
  \`apply_ko.py\` fills untranslated entries of QGC's Korean translation
* \`qgc-$QGC_REF-to-mobilitylab.diff\` — the complete difference as one unified diff
EOF
(cd "$WORK" && zip -qr9 "$OUT/$N-changes-vs-QGC-$QGC_REF.zip" "$(basename "$CH")")

# ---- 6-11. documents -------------------------------------------------------------------
DOC="$WORK/$N-docs"
mkdir -p "$DOC/licenses"
python3 mlgcs/tools/test_report.py "$RES" "$DOC/TEST_RESULTS.md"
cp mlgcs/docs/BUILD.md mlgcs/docs/USER_MANUAL.md mlgcs/docs/ARCHITECTURE.md mlgcs/docs/STATUS.md mlgcs/docs/LICENSES.md "$DOC/"
cp mlgcs/CHANGELOG.md "$DOC/"
cp mlgcs/vendor/acact_guard/ORIGIN.md "$DOC/ACACT_ORIGIN.md"
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
