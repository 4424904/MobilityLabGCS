#!/usr/bin/env python3
"""
stress_check.py — 나쁜 조건에서 시나리오를 여러 번 돌려 최악값 확인
  python3 stress_check.py S7_duo 20 --profile oregon2 --drones D1,D2
조건: 기준 / GPS ±2·±3 m / 통신 지연 0.5 s + 손실 15% / Offboard 전환 1.0 s / 가속 저하 / 돌풍 1 m/s / 복합
"""
import sys
import sim_check as S
import config as C
if '--profile' in sys.argv:
    C.PROFILE = sys.argv[sys.argv.index('--profile') + 1]
print(f'프로파일 {C.PROFILE}, 기체 {[d["id"] for d in C.DRONES]}')
name=sys.argv[1]; N=int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 20
cases={
 "기준":{},
 "GPS±2":{"gps":2.0},
 "GPS±3":{"gps":3.0},
 "통신지연0.5s+손실15%":{"lat":0.5,"drop":0.15},
 "전환지연1.0s":{"sw":1.0},
 "가속1.0":{"acc":1.0},
 "돌풍1.0m/s":{"gust":1.0},
 "복합(GPS2·지연0.3·손실10%·전환0.6·가속1.2·돌풍0.6)":{"gps":2.0,"lat":0.3,"drop":0.10,"sw":0.6,"acc":1.2,"gust":0.6},
}
for k,c in cases.items():
    S.TELEM_LAT=c.get("lat",0.15); S.TELEM_DROP=c.get("drop",0.0); S.OB_SWITCH=c.get("sw",0.35); S.ACC_H=c.get("acc",1.5); S.GUST=c.get("gust",0.0)
    rs=[S.run(name,'demo',seed=s,gps_err=c.get("gps",1.0),plot=False) for s in range(1,N+1)]
    mins=sorted(r['minh_same_layer'] for r in rs)
    print(f"{k:<45} 최소 {mins[0]:4.1f} m | 하위10% {mins[max(0,N//10-1)]:4.1f} | 중앙 {mins[N//2]:4.1f} | 5m미만 {sum(1 for x in mins if x<5)}/{N} | 착륙 {sum(r['all_landed'] for r in rs)}/{N}", flush=True)
