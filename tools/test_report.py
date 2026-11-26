#!/usr/bin/env python3
"""Test results of one CI run as Markdown (deliverable "구현 현황 및 테스트 결과").
   usage: test_report.py <results-dir (downloaded artifacts)> <out.md>"""
import glob
import json
import os
import re
import sys

res, out = sys.argv[1], sys.argv[2]
L = []
run = os.environ.get("GITHUB_RUN_ID", "?")
sha = os.environ.get("GITHUB_SHA", "?")[:10]
L.append(f"# 테스트 결과\n\nCI run {run}, commit {sha}. 이 표는 같은 실행에서 만든 산출물로 시험한 결과입니다.\n")

def tail(path, pat):
    try:
        t = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return None
    m = re.findall(pat, t)
    return m

L.append("## 1. 원본 ACACT(수정1) ↔ C++ 엔진, 미션 검사, 분석\n")
L.append("| 시험 | 결과 |\n|---|---|")
for f in glob.glob(os.path.join(res, "*", "acact-verify.log")):
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith("{") or "결과" in line or "mission_check_test" in line:
            L.append(f"| {('동등성' if line.startswith('{') else '')} | `{line.strip()}` |")
for f in glob.glob(os.path.join(res, "*", "analysis-test.log")):
    for line in open(f, encoding="utf-8", errors="replace"):
        if line.startswith(("ok", "FAIL", "analysis_test")):
            L.append(f"| 분석·PDF | `{line.strip()}` |")

L.append("\n## 2. SITL (PX4 v1.16.2 SIH 2대 / ArduCopter, Ubuntu 24.04, AppImage)\n")
L.append("| 시험 | 판정 | 점검 항목 | 주요 수치 |\n|---|---|---|---|")
for f in sorted(glob.glob(os.path.join(res, "*", "sitl-*.json"))):
    try:
        r = json.load(open(f))
    except Exception as e:
        L.append(f"| {os.path.basename(f)} | 읽기 실패 | {e} | |")
        continue
    ch = r.get("checks", {})
    ok = bool(ch) and all(ch.values())
    met = {k: v for k, v in r.get("metrics", {}).items() if k not in ("modes", "seq_history")}
    L.append(f"| {r.get('case') or r.get('fw')} | {'통과' if ok else '실패'} | {', '.join(k + ('' if v else ' ✗') for k, v in ch.items()) or '—'} | `{json.dumps(met, ensure_ascii=False)[:300]}` |")

L.append("\n## 3. Windows 설치 파일 · 포터블\n")
for f in glob.glob(os.path.join(res, "*", "results.json")):
    try:
        r = json.load(open(f, encoding="utf-8-sig"))
    except Exception as e:
        L.append(f"읽기 실패: {e}")
        continue
    L.append(f"환경: {r.get('os')}\n")
    L.append("| 점검 | 결과 |\n|---|---|")
    for k, v in r.get("checks", {}).items():
        L.append(f"| {k} | {'통과' if v else '실패'} |")
    for n in r.get("notes", []):
        L.append(f"\n- {n}")

L.append("\n## 4. 이 시험에 포함되지 않은 것\n")
L.append("- 실기체 비행 (SITL 만 수행)\n- Windows 11 실기 PC (CI 는 Windows Server 2022)\n- 실제 텔레메트리 모뎀·조종기 개입\n- 영상(GStreamer) 수신")
open(out, "w", encoding="utf-8").write("\n".join(L) + "\n")
print(f"wrote {out}")
