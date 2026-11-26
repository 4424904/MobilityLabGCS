#!/usr/bin/env bash
# ACACT equivalence: original rev1 Python guard (vendor/acact_guard/rev1) vs the C++ engine (custom/src/acact)
# usage: tools/acact_verify/run.sh [out_dir]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="${1:-$ROOT/build/acact_verify}"
mkdir -p "$OUT"
python3 -c "import numpy" 2>/dev/null || pip install --quiet numpy
g++ -std=c++17 -O2 -fPIC -shared -I"$ROOT/custom/src/acact" \
    "$ROOT/custom/src/acact/AcactCore.cc" "$ROOT/custom/src/acact/AcactScenarios.cc" "$HERE/acact_capi.cc" \
    -o "$OUT/libacact_capi.so"
python3 "$HERE/acact_compare.py" --lib "$OUT/libacact_capi.so" --json "$OUT/acact_compare.json"
python3 "$HERE/acact_compare_missions.py" "$OUT/libacact_capi.so"
# user-mission pre-flight check: regression cases
g++ -std=c++17 -O1 -Wall -Wextra -I"$ROOT/custom/src/acact" "$ROOT/custom/src/acact/AcactMissionCheck.cc" "$HERE/mission_check_test.cc" -o "$OUT/mission_check_test"
"$OUT/mission_check_test"
