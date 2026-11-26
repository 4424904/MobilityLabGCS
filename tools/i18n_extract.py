#!/usr/bin/env python3
"""Collect every Korean UI string of the MobilityLab code (QML qsTr, C++ tr, ACACT parameter labels,
ACACT engine event texts) and check custom/i18n/en.json against it.

  python3 tools/i18n_extract.py            report missing / unused entries (exit 1 if any are missing)
  python3 tools/i18n_extract.py --update   add missing keys to en.json with an empty value
The GCS shows English when the operator picks English (MLUi.language = "en"); MLJsonTranslator
looks the Korean source text up in en.json."""
import glob
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
EN = os.path.join(ROOT, "custom", "i18n", "en.json")
HANGUL = re.compile("[가-힣]")


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def collect():
    out = set()
    for f in glob.glob(os.path.join(ROOT, "custom", "qml", "**", "*.qml"), recursive=True):
        if f.endswith("MLAcactTestDriver.qml"):
            continue
        t = open(f, encoding="utf-8").read()
        for m in re.finditer(r'qsTr\("((?:[^"\\]|\\.)*)"', t):
            if HANGUL.search(m.group(1)):
                out.add(unescape(m.group(1)))
    for f in glob.glob(os.path.join(ROOT, "custom", "src", "*.cc")):
        t = open(f, encoding="utf-8").read()
        for m in re.finditer(r'\btr\("((?:[^"\\]|\\.)*)"', t):
            if HANGUL.search(m.group(1)):
                out.add(unescape(m.group(1)))
        # parameter tables: {"key", "label", "group", ...}
        for m in re.finditer(r'\{"\w+",\s*"([^"]*)",\s*"([^"]*)"', t):
            for g in m.groups():
                if HANGUL.search(g):
                    out.add(g)
    # scenario titles (engine, shown through tr())
    t = open(os.path.join(ROOT, "custom", "src", "acact", "AcactScenarios.cc"), encoding="utf-8").read()
    for m in re.finditer(r'\{"S\d\w*",\s*"([^"]*)"\}', t):
        out.add(m.group(1))
    return out


def main():
    keys = collect()
    data = json.load(open(EN, encoding="utf-8")) if os.path.exists(EN) else {}
    missing = sorted(k for k in keys if not data.get(k))
    unused = sorted(k for k in data if k not in keys and not k.startswith("_"))
    if "--update" in sys.argv:
        for k in missing:
            data.setdefault(k, "")
        json.dump(dict(sorted(data.items())), open(EN, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"{len(keys)} strings, {len(missing)} without English, {len(unused)} unused")
    for k in missing[:40]:
        print("  missing:", k)
    sys.exit(1 if missing and "--update" not in sys.argv else 0)


if __name__ == "__main__":
    main()
