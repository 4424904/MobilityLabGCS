#!/usr/bin/env python3
"""Merge translation batches (tools/i18n/*.json, Korean → English) into custom/i18n/en.json:
adds missing keys (tools/i18n_extract.py --update) and fills empty values. Existing translations stay."""
import glob, json, os, subprocess, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
EN = os.path.join(ROOT, "custom", "i18n", "en.json")
subprocess.run([sys.executable, os.path.join(ROOT, "tools", "i18n_extract.py"), "--update"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
en = json.load(open(EN, encoding="utf-8"))
for f in sorted(glob.glob(os.path.join(ROOT, "tools", "i18n", "*.json"))):
    for k, v in json.load(open(f, encoding="utf-8")).items():
        if k in en and not en[k]:
            en[k] = v
json.dump(dict(sorted(en.items())), open(EN, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
empty = [k for k, v in en.items() if not v]
print(f"{len(en)} entries, {len(empty)} empty")
for k in empty:
    print("  empty:", k)
