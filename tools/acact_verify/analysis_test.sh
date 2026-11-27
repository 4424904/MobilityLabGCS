#!/usr/bin/env bash
# Build and run the post-flight analysis regression test (MLFlightAnalysis + PDF report).
#   usage: analysis_test.sh <qt-root (has bin/ or libexec/moc, include/, lib/)> <out-dir>
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
QT="$1"; OUT="$2"
mkdir -p "$OUT"
MOC="$QT/libexec/moc"; [[ -x "$MOC" ]] || MOC="$QT/bin/moc"
"$MOC" "$ROOT/custom/src/MLFlightAnalysis.h" -o "$OUT/moc_analysis.cpp"
g++ -std=c++17 -fPIC -I"$QT/include" -I"$QT/include/QtCore" -I"$QT/include/QtGui" -I"$QT/include/QtSvg" -I"$ROOT/custom/src" -DML_GCS_VERSION=\"test\" \
    "$ROOT/custom/src/MLFlightAnalysis.cc" "$OUT/moc_analysis.cpp" "$HERE/analysis_test.cc" \
    -L"$QT/lib" -Wl,-rpath,"$QT/lib" -lQt6Svg -lQt6Gui -lQt6Core -o "$OUT/analysis_test"
python3 "$HERE/make_test_log.py" "$OUT/logs"
QT_QPA_PLATFORM=offscreen "$OUT/analysis_test" "$OUT/logs"
cp "$OUT/logs/report.pdf" "$OUT/analysis-test-report.pdf"
