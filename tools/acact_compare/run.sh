#!/usr/bin/env bash
# ACACT 원본(Python) ↔ C++ 이식 동작 비교. CI 와 개발 PC 공용.
#   bash tools/acact_compare/run.sh [out_dir]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${1:-/tmp/acact_traces}"
python3 -m pip install --quiet numpy >/dev/null 2>&1 || true
python3 "$HERE/record_traces.py" "$OUT"
g++ -std=c++17 -O2 -Wall -I"$ROOT/custom/src/acact" "$HERE/compare.cpp" "$ROOT/custom/src/acact/AcactCore.cpp" -o "$OUT/acact_compare"
"$OUT/acact_compare" "$OUT"/*.trace | tee "$OUT/compare_result.txt"
