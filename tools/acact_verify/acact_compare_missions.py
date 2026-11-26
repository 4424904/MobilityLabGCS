#!/usr/bin/env python3
"""
acact_compare_missions.py — 시나리오 미션(scenarios.build)·좌표 변환(geo.Frame) 원본 ↔ C++ 비교
모든 시나리오 × demo/rehearsal × 프로파일 × 기체 조합에서 항목 하나하나(종류·위치·고도·대기·속도·태그)가 완전히 같아야 통과.
"""
import ctypes, json, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from acact_compare import load_ref


def main():
    lib = ctypes.CDLL(os.path.abspath(sys.argv[1]))
    lib.acact_build.argtypes = [ctypes.c_char_p] * 4 + [ctypes.c_double, ctypes.c_char_p, ctypes.c_int]
    lib.acact_frame.argtypes = [ctypes.c_double] * 7 + [ctypes.POINTER(ctypes.c_double)]
    buf = ctypes.create_string_buffer(1 << 20)
    sets = ["D1,D2", "D1,D3", "D2,D4", "D1,D2,D3", "D1,D2,D3,D4", "D1,D2,D4"]
    profiles = ["oregon", "oregon2", "hwaseong"]
    n_items = n_cases = 0
    bad = []
    for ds in sets:
        for prof in profiles:
            C, core, sim = load_ref(ds, prof)
            SC = sys.modules["scenarios"]
            for name in SC.SCENARIOS:
                if not SC.available(name):
                    continue
                for mode in ("demo", "rehearsal"):
                    py = SC.build(name, mode)
                    n = lib.acact_build(ds.encode(), prof.encode(), name.encode(), mode.encode(), C.D_SAFE, buf, len(buf))
                    rows = [l.split("\t") for l in buf.value.decode().splitlines()]
                    cpp = {}
                    for r in rows:
                        cpp.setdefault(r[0], []).append(r[1:])
                    n_cases += 1
                    if sorted(py) != sorted(cpp):
                        bad.append(f"{ds}/{prof}/{name}/{mode}: 기체 {sorted(py)} ≠ {sorted(cpp)}")
                        continue
                    for d, items in py.items():
                        if len(items) != len(cpp[d]):
                            bad.append(f"{ds}/{prof}/{name}/{mode}/{d}: 항목 수 {len(items)} ≠ {len(cpp[d])}")
                            continue
                        for k, (it, c) in enumerate(zip(items, cpp[d])):
                            n_items += 1
                            typ, f, r, ha, alt, hh, hold, v, tag = c
                            p = it.get("p", (0.0, 0.0))
                            ok = (it["t"] == typ and float(f) == float(p[0]) and float(r) == float(p[1])
                                  and (("alt" in it) == (ha == "1")) and (("alt" not in it) or float(it["alt"]) == float(alt))
                                  and (("hold" in it) == (hh == "1")) and (("hold" not in it) or float(it["hold"]) == float(hold))
                                  and (it["t"] != "speed" or float(it["v"]) == float(v))
                                  and it.get("tag", "") == tag)
                            if not ok:
                                bad.append(f"{ds}/{prof}/{name}/{mode}/{d}#{k}: {it} ≠ {c}")
    # geo
    geo = sys.modules["geo"] if "geo" in sys.modules else __import__("geo")
    rng = random.Random(7)
    out = (ctypes.c_double * 4)()
    n_geo = 0
    for _ in range(2000):
        lat0, lon0, b = rng.uniform(-60, 60), rng.uniform(-179, 179), rng.uniform(0, 360)
        lat, lon = lat0 + rng.uniform(-0.01, 0.01), lon0 + rng.uniform(-0.01, 0.01)
        f, r = rng.uniform(-300, 300), rng.uniform(-300, 300)
        fr = geo.Frame(lat0, lon0, b)
        a1 = fr.ll_to_fr(lat, lon)
        a2 = fr.fr_to_ll(f, r)
        lib.acact_frame(lat0, lon0, b, lat, lon, f, r, out)
        n_geo += 1
        if max(abs(a1[0] - out[0]), abs(a1[1] - out[1])) > 1e-9 or max(abs(a2[0] - out[2]), abs(a2[1] - out[3])) > 1e-12:
            bad.append(f"geo {lat0},{lon0},{b}: {a1}{a2} ≠ {list(out)}")
    print(json.dumps({"cases": n_cases, "items": n_items, "geo": n_geo, "mismatch": len(bad)}, ensure_ascii=False))
    for b in bad[:15]:
        print("  ", b)
    print("결과:", "모두 일치" if not bad else "불일치 있음")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
