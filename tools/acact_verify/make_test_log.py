#!/usr/bin/env python3
"""Synthetic ACACT guard log for tools/acact_verify/analysis_test.cc: D1/D2 head-on at 8 m, D2 dodges 55–65 s, D2 link gap 90–93 s."""
import math, json, os, sys
d=sys.argv[1]; os.makedirs(d, exist_ok=True)
st="20261126_101500"
ids=["D1","D2"]
with open(f"{d}/guard_{st}.csv","w") as f:
    f.write("t"+"".join(f",{i}_{c}" for i in ids for c in ["mode","f","r","alt","vf","vr","own","fresh","wp"])+",min_pair,min_dist\n")
    for k in range(0, 20*120):
        t=10+k/20
        # D1 flies +R, D2 flies -R on the same line at 8 m; D2 dodges between 50-60 s
        x1=-30+0.6*(t-10); x2=30-0.6*(t-10)
        own2= 1 if 55<t<65 else 0
        f2= 6*math.sin(math.pi*(t-55)/10) if own2 else 0
        alt= min(8,(t-10)*1.0)
        fresh2 = 0 if 90<t<93 else 1
        row=[f"{t:.2f}","MISSION",f"0",f"{x1:.2f}",f"{alt:.2f}","0","0.6","0","1","3",
             "OFFBOARD" if own2 else "MISSION",f"{f2:.2f}",f"{x2:.2f}",f"{alt:.2f}","0","-0.6",str(own2),str(fresh2),"3","D1-D2","9"]
        f.write(",".join(row)+"\n")
json.dump({"version":1,"app":"test","opMode":"sim","plan":"S7_duo / 본 시연","vehicles":[{"id":"D1","sysid":1,"supported":True,"sim":1},{"id":"D2","sysid":2,"supported":True,"sim":1}],
 "cfg":{"dSafe":12,"dEmerg":5.5,"vSep":4},"site":{"lat":37.21,"lon":126.83,"bearing":0}}, open(f"{d}/guard_{st}_meta.json","w"))
open(f"{d}/guard_{st}_events.csv","w").write('t,who,event\n55.00,D2,"회피 개입 (Offboard)"\n65.00,D2,"회피 완료 → 미션 복귀"\n')
