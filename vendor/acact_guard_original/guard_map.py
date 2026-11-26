#!/usr/bin/env python3
"""
guard_map.py — 시연용 실시간 지도 화면 (가드와 별도 프로세스)
════════════════════════════════════════════════════════════════
guard.py 가 UDP(127.0.0.1:47000)로 보내는 상태를 그린다.
이 창이 멈추거나 닫혀도 가드 동작에는 영향이 없다.
  python3 guard_map.py            # 일반 창
  python3 guard_map.py --full     # 전체화면 (프로젝터 연결 시)
화면 문구는 현지 참관자용으로 영문.
"""
import argparse
import json
import socket

import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation
from matplotlib.patches import Circle, FancyArrow

import config as C

COL = {"D1": "#e4572e", "D2": "#2e86de", "D3": "#2ca02c", "D4": "#8e44ad"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--drones", default=None, help="일부 기체만 (예: D1,D3). 생략 시 4대")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--span", type=float, default=45.0)
    a = ap.parse_args()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(C.MAP_UDP)
    sock.setblocking(False)

    plt.rcParams["toolbar"] = "None"
    fig = plt.figure(figsize=(13, 8), facecolor="#0e1117")
    ax = fig.add_axes([0.03, 0.06, 0.62, 0.86], facecolor="#0e1117")
    side = fig.add_axes([0.67, 0.06, 0.31, 0.86], facecolor="#0e1117")
    side.axis("off")
    if a.full:
        try:
            fig.canvas.manager.full_screen_toggle()
        except Exception:
            pass
    fig.suptitle("MOBILITY LAB  |  ACACT Multi-UAV Collision Avoidance — Live",
                 color="white", fontsize=15, fontweight="bold", x=0.03, ha="left")
    state = {"msg": None}

    def draw(_):
        try:
            while True:
                data, _ = sock.recvfrom(65535)
                state["msg"] = json.loads(data.decode())
        except BlockingIOError:
            pass
        m = state["msg"]
        ax.clear()
        side.clear()
        side.axis("off")
        s = a.span
        ax.set_xlim(-s, s)
        ax.set_ylim(-s, s * 0.9)
        ax.set_aspect("equal")
        ax.set_facecolor("#0e1117")
        ax.tick_params(colors="#888")
        for sp in ax.spines.values():
            sp.set_color("#333")
        ax.grid(color="#222", lw=0.6)
        ax.add_patch(Circle((0, 0), C.SCENARIO_RADIUS, fill=False, ls=":", color="#555"))
        ax.axhline(C.HOME_LINE_F, color="#444", lw=0.8)
        ax.text(0, C.HOME_LINE_F - 3.5, "TAKEOFF LINE  /  GCS", color="#777", ha="center", fontsize=9)
        ax.set_xlabel("Right [m]", color="#888")
        ax.set_ylabel("Forward [m]", color="#888")
        if m is None:
            ax.text(0, 0, "waiting for guard...", color="#aaa", ha="center", fontsize=14)
            return
        # 쌍
        dm = {d["id"]: d for d in m["drones"]}
        for p in m["pairs"]:
            A, B = dm.get(p["a"]), dm.get(p["b"])
            if not A or not B:
                continue
            c = {0: "#666", 1: "#f5c518", 2: "#ff3b3b"}[p["level"]]
            ax.plot([A["r"], B["r"]], [A["f"], B["f"]], color=c, lw=1.5 if p["level"] else 0.8, ls="-" if p["level"] else "--")
            ax.text((A["r"] + B["r"]) / 2, (A["f"] + B["f"]) / 2, f"{p['d']:.1f} m", color=c, fontsize=10,
                    ha="center", va="bottom", fontweight="bold" if p["level"] else "normal")
        # 기체
        for d in m["drones"]:
            col = COL.get(d["id"], "white")
            alpha = 1.0 if d["fresh"] else 0.35
            ring = "#ff3b3b" if d["own"] else col
            ax.add_patch(Circle((d["r"], d["f"]), C.D_SAFE / 2, fill=False, ls="--", lw=1.0, color=ring, alpha=0.6 * alpha))
            ax.plot(d["r"], d["f"], "o", ms=13, color=col, alpha=alpha, mec="white" if d["own"] else col, mew=2)
            sp = (d["vf"] ** 2 + d["vr"] ** 2) ** 0.5
            if sp > 0.2:
                ax.add_patch(FancyArrow(d["r"], d["f"], d["vr"] * 2.5, d["vf"] * 2.5, width=0.25,
                                        head_width=1.2, color=col, alpha=alpha))
            if d.get("goal"):
                ax.plot(d["goal"][1], d["goal"][0], "x", color=col, ms=7, alpha=0.6)
            tag = "AVOIDING" if d["own"] else ("YIELDING" if d.get("yield") else d["mode"])
            if not d["fresh"]:
                tag = "LINK LOST"
            ax.text(d["r"] + 1.8, d["f"] + 1.8, f"{d['id']}  {d['alt']:.0f} m\n{tag}", color=col,
                    fontsize=9, alpha=alpha, fontweight="bold" if d["own"] or not d["fresh"] else "normal")
        # 사이드 패널
        y = 0.97
        side.text(0, y, "MINIMUM SEPARATION (same layer)", color="white", fontsize=11, fontweight="bold",
                  transform=side.transAxes)
        y -= 0.06
        for k, v in sorted(m["min_sep"].items()):
            c = "#3ddc84" if v >= 5.0 else "#ff3b3b"
            side.text(0.02, y, f"{k}", color="#bbb", fontsize=11, transform=side.transAxes)
            side.text(0.45, y, f"{v:5.1f} m", color=c, fontsize=11, fontweight="bold", transform=side.transAxes)
            y -= 0.045
        y -= 0.03
        n_av = sum(1 for d in m["drones"] if d["own"])
        side.text(0, y, f"UAVs under avoidance: {n_av}", color="#ff6b6b" if n_av else "#3ddc84",
                  fontsize=12, fontweight="bold", transform=side.transAxes)
        y -= 0.08
        side.text(0, y, "Target: min separation ≥ 5 m, zero collisions", color="#999", fontsize=10,
                  transform=side.transAxes)
        y -= 0.08
        side.text(0, y, "EVENTS", color="white", fontsize=11, fontweight="bold", transform=side.transAxes)
        y -= 0.05
        for e in m.get("events", [])[-6:]:
            side.text(0.02, y, e[:46], color="#aaa", fontsize=8.5, transform=side.transAxes, family="monospace")
            y -= 0.04
        side.text(0, 0.0, "Operator: 1 GCS  |  4 UAVs  |  Mission + ACACT guard",
                  color="#666", fontsize=9, transform=side.transAxes)

    _ani = FuncAnimation(fig, draw, interval=200, cache_frame_data=False)
    plt.show()


if __name__ == "__main__":
    main()
