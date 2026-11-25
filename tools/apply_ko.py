#!/usr/bin/env python3
"""Fill English-only entries of QGC's Korean translation with custom/i18n/ko_overrides.json.

Run from the QGC source root before configuring (tools/ci_prepare.sh does this).
Only operational UI contexts are touched (fly/plan view, toolbar indicators,
guided actions, multi-vehicle); firmware-plugin contexts are left alone so
flight-mode names keep matching the autopilot documentation.
"""
import html
import json
import re
import sys

TS = "translations/qgc_source_ko_KR.ts"
OVR = sys.argv[1] if len(sys.argv) > 1 else "mlgcs/custom/i18n/ko_overrides.json"

CONTEXTS = re.compile(
    r"^(GuidedAction|FlyView|MultiVehicle|Plan|Mission|SimpleItem|Takeoff|Transect|Survey|PreFlight|"
    r"MainStatus|FlightMode|Battery|GPS|Message|Telemetry|RC|Toolbar|MainWindow|QGroundControl|"
    r"VehicleWarnings|GeoFence|Rally|Land|MapScale|QGCMap|Vehicle$|MultiVehicleManager|VTOL|"
    r"ComplexMission|FWLanding|MissionCommandTree|MissionSettings|MissionItem|PlanMaster|ToolStrip)")
HANGUL = re.compile("[가-힣]")

overrides = {k: v for k, v in json.load(open(OVR, encoding="utf-8")).items() if not k.startswith("_")}
text = open(TS, encoding="utf-8").read()

count = 0


def fix_context(match):
    global count
    block = match.group(0)
    name = re.search(r"<name>(.*?)</name>", block, re.S).group(1)
    if not CONTEXTS.match(name):
        return block

    def fix_message(m):
        global count
        msg = m.group(0)
        src = re.search(r"<source>(.*?)</source>", msg, re.S)
        tr = re.search(r"<translation([^>]*)>(.*?)</translation>|<translation([^>]*)/>", msg, re.S)
        if not src or not tr or "numerusform" in msg:
            return msg
        source = html.unescape(src.group(1))
        current = html.unescape(tr.group(2) or "")
        if HANGUL.search(current) or source not in overrides:
            return msg
        count += 1
        new = "<translation>" + html.escape(overrides[source], quote=False) + "</translation>"
        return msg[:tr.start()] + new + msg[tr.end():]

    return re.sub(r"<message[^>]*>.*?</message>", fix_message, block, flags=re.S)


text = re.sub(r"<context>.*?</context>", fix_context, text, flags=re.S)
open(TS, "w", encoding="utf-8").write(text)
print(f"apply_ko: {count} Korean strings filled in {TS}")
