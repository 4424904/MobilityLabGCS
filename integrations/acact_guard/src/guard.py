#!/usr/bin/env python3
"""
guard.py — ACACT 충돌 가드 (실기 / PX4 SITL 공용)
════════════════════════════════════════════════════════════════
4대가 QGC 미션으로 비행하는 동안 감시하다가, 충돌 위험이 예측되면 해당 기체만
Offboard 로 넘겨받아 ACACT 회피 후 미션으로 되돌린다.

실행 전:
  - mavsdk 는 반드시 3.x (gRPC) 버전:  pip install "mavsdk<4"
  - 기체별 mavsdk_server 4개 실행 (README 참고)
  - plan_gen.py 로 만든 plans/site.json 이 있으면 시연 프레임·이륙지점 점검에 사용

운용 명령 (입력 후 Enter):
  load S3_cross4 demo : 4대에 해당 시나리오 미션을 기체별로 정확히 업로드 (지상에서만)
  start               : D4→D1 (높은 층부터) 5초 간격 시동·미션 시작 (사전 점검 통과 시)
  auto on|off : 자동 진행 (기본 켜짐) — 4대 도착·정지 5초 후 자동으로 다음 기동·착륙
  g   : 동기 출발 — SYNC(LOITER_UNLIM) 대기 중인 기체를 동시에 다음 구간으로
  g!  : 일부만 대기 중이어도 대기 중인 기체만 출발
  h   : 전 기체 HOLD (가드 개입도 해제)
  r   : HOLD 중인 기체 미션 재개
  s   : 상태 출력
  q   : 종료 (가드가 잡고 있던 기체는 HOLD 로 전환 후 종료)
"""
import argparse
import asyncio
import csv
import json
import math
import os
import socket
import sys
import threading
import time
import traceback

import config as C
from core import GuardCore, DroneIn
from geo import Frame, load_site
from gcs_link import GcsLink
from servers import Servers

try:
    from mavsdk import System
    from mavsdk.offboard import OffboardError, VelocityNedYaw
    from mavsdk.telemetry import FlightMode
except Exception as e:   # mavsdk 4.x 등
    print("mavsdk(gRPC) 임포트 실패:", e)
    print('→ pip install "mavsdk<4"  (mavsdk 4.x 는 API 가 달라 사용할 수 없음)')
    sys.exit(1)

NAV_POS_CMDS = {16, 17, 18, 19, 21, 22}
CMD_LOITER_UNLIM = 17
CMD_LAND = 21

MODE_MAP = {
    "MISSION": "MISSION", "OFFBOARD": "OFFBOARD", "HOLD": "HOLD",
    "RETURN_TO_LAUNCH": "RTL", "LAND": "LAND", "TAKEOFF": "TAKEOFF",
}


class DS:
    """기체 런타임 상태"""
    def __init__(self, cfg, prio):
        self.cfg = cfg
        self.id = cfg["id"]
        self.prio = prio
        self.sys = None
        self.connected = False
        self.lat = self.lon = None
        self.abs_alt = self.rel_alt = 0.0
        self.vn = self.ve = self.vd = 0.0
        self.yaw = 0.0
        self.mode = "OTHER"
        self.in_air = False
        self.armed = False
        self.batt = None
        self.gps_fix = None
        self.sats = 0
        self.t_pos = -1e9
        self.items = []          # mission_raw items
        self.cur = 0
        self.total = 0
        self.home = None
        self.busy = False
        self.xt_max = 0.0
        self.xt_sq = 0.0
        self.xt_n = 0
        self.t_release = -1e9
        self.sysid = None
        self.reloading = False
        self.orphan_since = None
        self.max_gap = 0.0
        self.rc_ok = None
        self.batt_warned = False
        self.t_take_cmd = None
        self.switch_lat = []


class Guard:
    def __init__(self, args):
        self.args = args
        self.ds = [DS(c, i) for i, c in enumerate(C.DRONES)]
        self.core = GuardCore([d.id for d in self.ds])
        self.site = load_site(args.site)
        self.frame = None
        if self.site:
            self.frame = Frame(self.site["center_lat"], self.site["center_lon"], self.site["bearing_deg"])
        self.t0 = time.monotonic()
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.quit = False
        os.makedirs(C.LOG_DIR, exist_ok=True)
        stamp = time.strftime("%Y%m%d_%H%M%S")
        self.log_path = os.path.join(C.LOG_DIR, f"guard_{stamp}.csv")
        self.ev_path = os.path.join(C.LOG_DIR, f"events_{stamp}.csv")
        self.sum_path = os.path.join(C.LOG_DIR, f"summary_{stamp}.txt")
        self.logf = open(self.log_path, "w", newline="")
        self.log = csv.writer(self.logf)
        hdr = ["t"]
        for d in self.ds:
            hdr += [f"{d.id}_{k}" for k in ("mode", "F", "R", "alt", "vF", "vR", "own", "fresh", "seq")]
        hdr += ["min_pair", "min_dist"]
        self.log.writerow(hdr)
        self.evf = open(self.ev_path, "w", newline="")
        self.ev = csv.writer(self.evf)
        self.ev.writerow(["t", "who", "event"])
        self.events_recent = []
        self.servers = None
        self.last_tick_real = time.monotonic()
        self.tick_errors = 0
        self.loop_running = False
        self._shut = False
        self.auto = C.AUTO_SYNC
        self.auto_since = None
        self.auto_land_told = False
        self.auto_bad_since = None
        self.auto_told_at = None
        self.last_sync_t = -1e9
        self.gcs = GcsLink(self)       # MobilityLab GCS 연결 (상태 송신·명령 수신)

    # ── 워치독: 메인 루프가 1초 이상 멈추면 mavsdk_server 를 죽여 setpoint 스트림을 끊는다 ──
    def _watchdog(self):
        import time as _t
        while not self.quit:
            _t.sleep(0.2)
            if self.loop_running and _t.monotonic() - self.last_tick_real > 1.0 and self.servers:
                print("\n[WATCHDOG] 가드 메인 루프 정지 감지 → mavsdk_server 강제 종료 "
                      "(회피 중 기체는 PX4 offboard 상실 → Hold, 나머지는 미션 계속)", flush=True)
                self.servers.kill_now()
                os._exit(2)

    # ── 유틸 ────────────────────────────────────────────
    def now(self):
        return time.monotonic() - self.t0

    EN = [("회피 개입", "AVOIDANCE START"), ("미션 복귀", "back to mission"), ("텔레메트리 끊김", "LINK LOST"),
          ("동기 출발", "synchronized start"), ("HOLD", "HOLD"), ("위험 근접", "close approach (no avoidable UAV)"),
          ("전환 감지", "pilot override"), ("연결됨", "connected"), ("모드 →", "mode change"), ("미션", "mission")]

    def event(self, who, text):
        t = self.now()
        print(f"[{t:7.1f}] {who:>5} | {text}")
        self.ev.writerow([f"{t:.2f}", who, text])
        self.evf.flush()
        en = next((e for k, e in self.EN if k in text), "event")
        if "모드 →" in text:
            en = "mode " + text.split("→")[-1].strip()
        self.events_recent = (self.events_recent + [f"{t:6.1f}s {who} {en}"])[-6:]
        if getattr(self, "gcs", None) is not None:
            self.gcs.on_event(t, who, text)

    def fr(self, lat, lon):
        return self.frame.ll_to_fr(lat, lon)

    def v_fr(self, vn, ve):
        return self.frame.ne_to_fr(vn, ve)

    def v_ne(self, vf, vr):
        return self.frame.fr_to_ne(vf, vr)

    # ── 연결 / 텔레메트리 ────────────────────────────────
    async def connect(self, d: DS):
        d.sys = System(mavsdk_server_address=self.args.host, port=d.cfg["port"])
        await d.sys.connect()
        async for st in d.sys.core.connection_state():
            if st.is_connected:
                d.connected = True
                break
        self.event(d.id, f"연결됨 (gRPC {d.cfg['port']})")
        for coro in (self.sub_pos, self.sub_vel, self.sub_mode, self.sub_air, self.sub_armed, self.sub_rc,
                     self.sub_att, self.sub_batt, self.sub_gps, self.sub_progress, self.sub_home,
                     self.sub_mission_changed):
            asyncio.ensure_future(self._forever(coro, d))
        try:
            d.sysid = await d.sys.param.get_param_int("MAV_SYS_ID")
        except Exception:
            d.sysid = None
        await self.download_mission(d)
        # MAVSDK 는 setpoint 를 한 번 설정하면 내부에서 계속 재송신한다.
        # 대기 중에는 0 속도를 흘려 두어 개입 시 Offboard 전환이 즉시 되도록 한다 (미션 중에는 PX4 가 무시).
        try:
            await d.sys.offboard.set_velocity_ned(VelocityNedYaw(0.0, 0.0, 0.0, d.yaw))
        except Exception:
            pass

    async def _forever(self, coro, d):
        while not self.quit:
            try:
                await coro(d)
            except Exception as e:
                await asyncio.sleep(1.0)

    async def sub_pos(self, d):
        try:
            await d.sys.telemetry.set_rate_position(C.TELEM_HZ)
        except Exception:
            pass
        async for p in d.sys.telemetry.position():
            d.lat, d.lon = p.latitude_deg, p.longitude_deg
            d.abs_alt, d.rel_alt = p.absolute_altitude_m, p.relative_altitude_m
            d.t_pos = self.now()
            if self.frame is None:
                self.frame = Frame(d.lat, d.lon, 0.0)
                self.event("SYS", f"site.json 없음 → {d.id} 위치를 원점으로 사용 (방위 0°)")

    async def sub_vel(self, d):
        try:
            await d.sys.telemetry.set_rate_velocity_ned(C.TELEM_HZ)
        except Exception:
            pass
        async for v in d.sys.telemetry.velocity_ned():
            d.vn, d.ve, d.vd = v.north_m_s, v.east_m_s, v.down_m_s

    async def sub_att(self, d):
        async for a in d.sys.telemetry.attitude_euler():
            d.yaw = a.yaw_deg

    async def sub_mode(self, d):
        async for m in d.sys.telemetry.flight_mode():
            new = MODE_MAP.get(m.name, "MANUAL" if m.name in ("POSCTL", "ALTCTL", "MANUAL", "STABILIZED", "ACRO") else "OTHER")
            if new != d.mode:
                if new == "OFFBOARD" and d.t_take_cmd is not None:
                    d.switch_lat.append(self.now() - d.t_take_cmd)
                    d.t_take_cmd = None
                d.mode = new
                if self.core.own[d.id].owned or new in ("RTL", "LAND", "MANUAL"):
                    self.event(d.id, f"모드 → {m.name}")
                # 비상 귀환·착륙(통신 두절, 배터리 부족, 지오펜스, QGC 조작 등): 자동 진행 정지
                #   (가드는 RTL·LAND 를 보내지 않으므로 이 모드는 항상 PX4 안전기능이나 사람이 건 것)
                if new in ("RTL", "LAND") and d.in_air and self.auto:
                    self.auto = False
                    self.event("AUTO", f"{d.id} 비상 귀환/착륙({m.name}) — 자동 진행 정지. 확인 후 'auto on' 또는 'g!'")
                # 조종기 수동 개입: 그 기체는 가드가 손을 떼고(장애물로만 취급), 자동 진행은 정지
                if new == "MANUAL" and d.in_air:
                    self.event(d.id, "※ 조종기 수동 개입 감지 — 가드는 이 기체를 피하기만 함")
                    if self.auto:
                        self.auto = False
                        self.event("AUTO", "수동 개입으로 자동 진행 정지 — 상황 정리 후 'auto on' 또는 'g'")

    async def sub_rc(self, d):
        try:
            async for r in d.sys.telemetry.rc_status():
                d.rc_ok = bool(r.is_available)
        except Exception:
            pass

    async def sub_air(self, d):
        async for v in d.sys.telemetry.in_air():
            d.in_air = v

    async def sub_armed(self, d):
        async for v in d.sys.telemetry.armed():
            d.armed = v

    async def sub_batt(self, d):
        async for b in d.sys.telemetry.battery():
            v = b.remaining_percent
            d.batt = v * 100.0 if v is not None and v <= 1.0 else v   # 버전에 따라 0~1 또는 0~100

    async def sub_gps(self, d):
        async for g in d.sys.telemetry.gps_info():
            d.gps_fix, d.sats = g.fix_type.name, g.num_satellites

    async def sub_home(self, d):
        async for h in d.sys.telemetry.home():
            d.home = (h.latitude_deg, h.longitude_deg)

    async def sub_progress(self, d):
        async for p in d.sys.mission_raw.mission_progress():
            d.cur, d.total = p.current, p.total

    async def sub_mission_changed(self, d):
        async for _ in d.sys.mission_raw.mission_changed():
            self.event(d.id, "미션 변경 감지 → 다시 다운로드")
            await self.download_mission(d)

    async def download_mission(self, d):
        d.reloading = True
        try:
            d.items = await d.sys.mission_raw.download_mission()
            self.event(d.id, f"미션 {len(d.items)}개 항목")
        except Exception as e:
            d.items = []
            self.event(d.id, f"미션 다운로드 실패/없음: {e}")
        finally:
            d.reloading = False

    # ── 미션 목표 ────────────────────────────────────────
    def _item_fr(self, it):
        return self.fr(it.x / 1e7, it.y / 1e7)

    def goal_of(self, d):
        if not d.items or self.frame is None:
            return None, None
        for k in range(d.cur, len(d.items)):
            it = d.items[k]
            if it.command in NAV_POS_CMDS and (it.x != 0 or it.y != 0):
                prev = None
                for j in range(k - 1, -1, -1):
                    pj = d.items[j]
                    if pj.command in NAV_POS_CMDS and (pj.x != 0 or pj.y != 0):
                        prev = pj
                        break
                return it, prev
        return None, None

    # ── 명령 ─────────────────────────────────────────────
    def _vel(self, d, v):
        vn, ve = self.v_ne(v[0], v[1])
        return VelocityNedYaw(vn, ve, -v[2], d.yaw_hold if hasattr(d, "yaw_hold") else d.yaw)

    async def takeover(self, d, v):
        d.busy = True
        d.yaw_hold = d.yaw
        d.t_take_cmd = self.now()
        try:
            sp = self._vel(d, v)
            if not self.core.enabled or not self.core.own[d.id].owned:
                return
            for _ in range(3):
                await d.sys.offboard.set_velocity_ned(sp)
                await asyncio.sleep(0.03)
            # ★ 조종사가 그 사이 조종기로 가져갔으면(수동 모드) 절대 빼앗지 않는다
            if not self._can_take(d):
                return
            try:
                await d.sys.offboard.start()
            except OffboardError:
                # setpoint 스트림이 충분하지 않았던 경우: 0.5 s 더 보내고 한 번 더 시도
                for _ in range(10):
                    await d.sys.offboard.set_velocity_ned(sp)
                    await asyncio.sleep(0.05)
                if not self._can_take(d):
                    return
                await d.sys.offboard.start()
            if not self.core.enabled:          # 전환 중에 'h' 가 눌렸으면 즉시 HOLD
                await d.sys.offboard.set_velocity_ned(VelocityNedYaw(0.0, 0.0, 0.0, d.yaw))
                await d.sys.action.hold()
                return
            self.event(d.id, "회피 개입 (Offboard)")
        except Exception as e:
            self.event(d.id, f"Offboard 전환 실패 ({e}) → HOLD")
            self.core.own[d.id].owned = False
            try:
                await d.sys.action.hold()
            except Exception:
                pass
        finally:
            d.busy = False

    def _can_take(self, d):
        """가드가 Offboard 로 가져가도 되는 상태인지 (미션 비행 중이고 사람이 조종하지 않음)"""
        if d.mode in ("MISSION", "OFFBOARD") and self.core.enabled and self.core.own[d.id].owned:
            return True
        self.core.own[d.id].owned = False
        if d.mode == "MANUAL":
            self.event(d.id, "조종기 개입 중 → 가드 회피 명령 취소")
        return False

    async def _stop_hold(self, d):
        try:
            await d.sys.offboard.set_velocity_ned(VelocityNedYaw(0.0, 0.0, 0.0, d.yaw))
            await d.sys.action.hold()
        except Exception:
            pass

    async def set_vel(self, d, v):
        try:
            await d.sys.offboard.set_velocity_ned(self._vel(d, v))
        except Exception:
            pass

    async def release(self, d):
        d.busy = True
        try:
            if d.mode != "OFFBOARD":       # 사람이 가져갔거나 PX4 가 다른 모드로 바꾼 경우: 미션으로 되돌리지 않음
                return
            await d.sys.mission_raw.start_mission()
            await d.sys.offboard.set_velocity_ned(VelocityNedYaw(0.0, 0.0, 0.0, d.yaw))
            self.event(d.id, "회피 완료 → 미션 복귀")
        except Exception as e:
            self.event(d.id, f"미션 복귀 실패 ({e}) → HOLD")
            try:
                await d.sys.action.hold()
            except Exception:
                pass
        finally:
            d.busy = False

    # ── 운용자 명령 ──────────────────────────────────────
    def sync_state(self):
        """대기점(LOITER_UNLIM) 도착 여부: (도착, 미도착, 다음이 착륙인지)"""
        ready, notready, landing = [], [], False
        for d in self.ds:
            if not d.connected or not d.in_air:
                continue
            at_loiter = False
            if d.cur < len(d.items) and d.items[d.cur].command == CMD_LOITER_UNLIM and d.mode in ("MISSION", "HOLD") \
                    and d.lat is not None:
                it = d.items[d.cur]
                f0, r0 = self.fr(it.x / 1e7, it.y / 1e7)
                f1, r1 = self.fr(d.lat, d.lon)
                # PX4 는 대기점으로 '가는 중'에도 현재 항목이 LOITER 로 표시됨 → 실제 도착(수평 2.5 m, 고도 1.5 m)까지 확인
                at_loiter = math.hypot(f1 - f0, r1 - r0) < 2.5 and abs(d.rel_alt - it.z) < 1.5
                if d.cur + 1 < len(d.items) and d.items[d.cur + 1].command == CMD_LAND:
                    landing = True
            (ready if at_loiter else notready).append(d)
        return ready, notready, landing

    async def cmd_sync(self, force=False):
        if not self.core.enabled:
            self.event("CMD", "가드 일시정지(HOLD) 상태 — 'r' 로 재개 후 'g'")
            return
        ready, notready, _ = self.sync_state()
        if not ready:
            self.event("CMD", "동기 대기(LOITER_UNLIM) 중인 기체 없음")
            return
        if notready and not force:
            self.event("CMD", f"대기 미도달: {[d.id for d in notready]} → 기다리거나 'g!' 로 강제")
            return
        self.last_sync_t = self.now()
        self.auto_since = None
        # 4대 동시 송신
        await asyncio.gather(*[d.sys.mission_raw.set_current_mission_item(d.cur + 1) for d in ready],
                             return_exceptions=True)
        await asyncio.gather(*[d.sys.mission_raw.start_mission() for d in ready if d.mode == "HOLD"],
                             return_exceptions=True)
        self.event("CMD", f"동기 출발: {[d.id for d in ready]}")

    def auto_tick(self, t):
        """자동 진행: 4대 모두 대기점 도착 + 정지 + 회피 없음 이 AUTO_SYNC_DELAY 동안 유지되면 다음 기동.
        착륙도 자동 (C.AUTO_LAND=False 면 착륙 직전만 사람이 'g')."""
        if not self.auto or not self.core.enabled or t - self.last_sync_t < 3.0:
            self.auto_since = None
            return
        ready, notready, landing = self.sync_state()
        settled = bool(ready) and not notready and all(
            math.hypot(d.vn, d.ve) < 0.5 and (t - d.t_pos) < C.STALE_T and not self.core.own[d.id].owned
            for d in ready)
        if not settled:
            # 센서 잡음으로 잠깐 조건이 깨지는 것은 무시 (1초 이상 지속될 때만 초기화)
            if self.auto_bad_since is None:
                self.auto_bad_since = t
            elif t - self.auto_bad_since > 1.0:
                self.auto_since = None
                self.auto_land_told = False
            return
        self.auto_bad_since = None
        if landing and not C.AUTO_LAND:
            if not self.auto_land_told:
                self.auto_land_told = True
                self.event("AUTO", f"{len(ready)}대 이륙지점 상공 도착 — 착륙은 확인 후 'g' 입력")
            return
        if self.auto_since is None:
            self.auto_since = t
            if self.auto_told_at != self.last_sync_t:
                self.auto_told_at = self.last_sync_t
                what = "착륙" if landing else "다음 기동"
                self.event("AUTO", f"{len(ready)}대 도착 — {C.AUTO_SYNC_DELAY:.0f}초 후 {what} (멈추려면 h)")
        elif t - self.auto_since >= C.AUTO_SYNC_DELAY:
            self.auto_since = None
            self.last_sync_t = t
            asyncio.ensure_future(self.cmd_sync())

    async def cmd_load(self, name, mode):
        if any(d.in_air or d.armed for d in self.ds if d.connected):
            self.event("CMD", "load 는 4대 모두 지상·시동 꺼짐 상태에서만 가능")
            return
        ok = True
        for d in self.ds:
            path = os.path.join(os.path.dirname(self.args.site or C.SITE_FILE), mode, name, f"{d.id}.plan")
            if not os.path.exists(path):
                self.event("CMD", f"파일 없음: {path}")
                return
            try:
                imp = await d.sys.mission_raw.import_qgroundcontrol_mission(path)
                await d.sys.mission_raw.upload_mission(imp.mission_items)
                try:
                    if imp.geofence_items:
                        await d.sys.mission_raw.upload_geofence(imp.geofence_items)
                except Exception as e:
                    self.event(d.id, f"지오펜스 업로드 실패 (미션은 정상): {e}")
                await self.download_mission(d)
                if len(d.items) != len(imp.mission_items):
                    ok = False
                    self.event(d.id, f"※ 업로드 검증 실패 ({len(d.items)} != {len(imp.mission_items)})")
                else:
                    self.event(d.id, f"{name}/{mode} 업로드 OK ({len(d.items)}개)")
            except Exception as e:
                ok = False
                self.event(d.id, f"※ 업로드 실패: {e}")
        self.loaded = (name, mode) if ok else None
        self.preflight()

    async def cmd_start(self):
        if not self.core.enabled:
            self.event("CMD", "가드 일시정지 상태 — 'r' 후 다시")
            return
        if any(d.in_air for d in self.ds if d.connected):
            self.event("CMD", "이미 비행 중인 기체가 있음 → start 불가 (QGC 로 개별 시작)")
            return
        if not self.preflight():
            self.event("CMD", "사전 점검 실패 → start 취소")
            return
        # 높은 층(D4)부터 이륙: 낮은 층 기체가 이동할 때 위 기체는 이미 자기 층에 올라가 있음
        for d in reversed(self.ds):
            if not self.core.enabled or self.quit:
                self.event("CMD", "start 중단됨 (HOLD/종료)")
                return
            try:
                await d.sys.action.arm()
                await d.sys.mission_raw.start_mission()
                self.event(d.id, "시동·미션 시작")
            except Exception as e:
                self.event(d.id, f"※ 시작 실패: {e} → 나머지 기체 시작 중단")
                return
            await asyncio.sleep(5.0)

    async def cmd_hold_all(self):
        self.core.enabled = False
        # 조종기로 수동 비행 중인 기체는 건드리지 않는다 (조종사 권한 우선)
        live = [d for d in self.ds if d.connected and d.in_air and d.mode != "MANUAL"]
        # 1) Offboard 중인 기체가 있어도 멈추도록 0 속도 먼저
        await asyncio.gather(*[d.sys.offboard.set_velocity_ned(VelocityNedYaw(0.0, 0.0, 0.0, d.yaw))
                               for d in live], return_exceptions=True)
        # 2) HOLD
        await asyncio.gather(*[d.sys.action.hold() for d in live], return_exceptions=True)
        self.event("CMD", "전 기체 HOLD (가드 일시정지) — 'r' 로 미션 재개")
        # 3) 전환 중이던 명령과 겹친 경우 대비: 1초 뒤 HOLD 아닌 기체에 한 번 더
        await asyncio.sleep(1.0)
        again = [d for d in live if d.mode not in ("HOLD", "RTL", "LAND", "MANUAL")]
        if again:
            await asyncio.gather(*[d.sys.action.hold() for d in again], return_exceptions=True)
            self.event("CMD", f"HOLD 재전송: {[d.id for d in again]}")

    async def cmd_resume(self):
        self.core.enabled = True
        await asyncio.gather(*[d.sys.mission_raw.start_mission() for d in self.ds
                               if d.connected and d.in_air and d.mode in ("HOLD", "OFFBOARD")
                               and not self.core.own[d.id].owned], return_exceptions=True)
        self.event("CMD", "HOLD 기체 미션 재개, 가드 활성")

    def status(self):
        print("-" * 96)
        for d in self.ds:
            f = r = float("nan")
            if d.lat is not None and self.frame:
                f, r = self.fr(d.lat, d.lon)
            age = self.now() - d.t_pos
            o = self.core.own[d.id]
            print(f" {d.id} {'연결' if d.connected else '----'} {d.mode:<8} 공중:{'Y' if d.in_air else 'N'} "
                  f"F{f:+6.1f} R{r:+6.1f} H{d.rel_alt:5.1f}m 배터리:{(d.batt or 0):4.0f}% "
                  f"GPS:{d.gps_fix}/{d.sats} 미션:{d.cur}/{len(d.items)} 수신:{age:4.1f}s "
                  f"{'[가드]' if o.owned else ''}{'[양보]' if o.yielding else ''}")
        for k, v in sorted(self.core.min_sep.items()):
            print(f"   {k[0]}-{k[1]} 같은 층 최소거리 {v:5.1f} m")
        print("-" * 96)

    async def stdin_loop(self):
        # 입력은 별도 스레드에서 읽는다 (Windows 의 이벤트 루프는 stdin 을 감시할 수 없음)
        loop = asyncio.get_event_loop()
        q = asyncio.Queue()
        eof_quit = os.environ.get("ACACT_STDIN_EOF_QUIT") == "1"   # GCS 가 띄운 경우: GCS 가 사라지면 종료

        def reader():
            while True:
                line = sys.stdin.readline()
                if line == "":
                    if eof_quit:
                        loop.call_soon_threadsafe(q.put_nowait, "q")
                    return
                loop.call_soon_threadsafe(q.put_nowait, line)

        threading.Thread(target=reader, daemon=True).start()
        while not self.quit:
            self.dispatch((await q.get()).strip())

    def dispatch(self, raw):
        """운용 명령 1줄 처리 (터미널 입력과 GCS 명령 공용)"""
        parts = raw.split()
        if not parts:
            return
        cmd = parts[0].lower()
        # 각 명령은 별도 작업으로 실행 → 'start'(20초) 진행 중에도 'h' 가 즉시 동작
        if cmd == "h":
            asyncio.ensure_future(self.cmd_hold_all())
        elif cmd == "load":
            if len(parts) < 2:
                print("사용: load S3_cross4 demo   (모드 생략 시 demo)")
            else:
                asyncio.ensure_future(self.cmd_load(parts[1], parts[2].lower() if len(parts) > 2 else "demo"))
        elif cmd == "start":
            asyncio.ensure_future(self.cmd_start())
        elif cmd == "auto":
            arg = parts[1].lower() if len(parts) > 1 else ""
            if arg in ("on", "off"):
                self.auto = (arg == "on")
            self.event("CMD", f"자동 진행 {'켜짐' if self.auto else '꺼짐'} (대기 {C.AUTO_SYNC_DELAY:.0f}초, 착륙 {'자동' if C.AUTO_LAND else '수동 g'})")
        elif cmd in ("g", "g!"):
            asyncio.ensure_future(self.cmd_sync(force=(cmd == "g!")))
        elif cmd == "r":
            asyncio.ensure_future(self.cmd_resume())
        elif cmd == "s":
            self.status()
        elif cmd == "q":
            self.quit = True
        else:
            print("명령: load <시나리오> [demo|rehearsal] / start / g / g! / auto on|off / h / r / s / q")

    # ── 사전 점검 ────────────────────────────────────────
    def preflight(self):
        ok = True
        print("\n================ 사전 점검 ================")
        for d in self.ds:
            msg = []
            if not d.connected:
                msg.append("연결 안 됨")
            if d.gps_fix and "FIX_3D" not in d.gps_fix and "RTK" not in d.gps_fix and "DGPS" not in d.gps_fix:
                msg.append(f"GPS {d.gps_fix}")
            if d.sats and d.sats < 10:
                msg.append(f"위성 {d.sats}개")
            if d.batt is not None and d.batt < 80:
                msg.append(f"배터리 {d.batt:.0f}%")
            if d.sysid is not None and d.sysid != d.cfg["sysid"]:
                msg.append(f"MAV_SYS_ID={d.sysid} (기대 {d.cfg['sysid']}) — 모뎀/포트가 바뀌었을 수 있음")
            if d.rc_ok is False:
                msg.append("조종기 신호 없음 — 해당 조종기 전원·바인딩 확인 (수동 개입 불가)")
            if not d.items:
                msg.append("미션 없음")
            elif d.lat is not None and not d.in_air:
                first = next((it for it in d.items if it.command in NAV_POS_CMDS and (it.x or it.y)), None)
                if first is not None:
                    f0, r0 = self.fr(first.x / 1e7, first.y / 1e7)
                    f1, r1 = self.fr(d.lat, d.lon)
                    if math.hypot(f1 - f0, r1 - r0) > 5.0:
                        msg.append(f"미션 이륙점이 현재 위치와 {math.hypot(f1 - f0, r1 - r0):.0f} m 다름 — 다른 기체 미션일 수 있음!")
            if self.site and d.lat is not None:
                hp = self.site.get("homes", {}).get(d.id)
                if hp:
                    f0, r0 = self.fr(hp[0], hp[1])
                    f1, r1 = self.fr(d.lat, d.lon)
                    dist = math.hypot(f1 - f0, r1 - r0)
                    if dist > 3.0:
                        msg.append(f"이륙 위치가 계획과 {dist:.1f} m 다름")
            if msg:
                ok = False
            print(f"  {d.id}: {'OK' if not msg else ' / '.join(msg)}")
        print("===========================================\n")
        return ok

    # ── 메인 루프 ────────────────────────────────────────
    loaded = None

    async def run(self):
        print(f"\nACACT Guard — 기체 {len(self.ds)}대, 로그: {self.log_path}")
        if not self.args.no_spawn:
            self.servers = Servers().start()
            print("mavsdk_server 4개를 가드 자식 프로세스로 실행 (가드 종료 시 함께 종료)")
        threading.Thread(target=self._watchdog, daemon=True).start()
        self.last_tick_real = time.monotonic()
        try:
            await asyncio.wait_for(asyncio.gather(*[self.connect(d) for d in self.ds]), timeout=60)
        except asyncio.TimeoutError:
            print("※ 60초 안에 연결되지 않은 기체가 있음:", [d.id for d in self.ds if not d.connected])
        self.last_tick_real = time.monotonic()
        await asyncio.sleep(2.0)
        if not self.preflight():
            print("※ 점검 항목을 확인하세요. 그래도 진행하려면 그대로 두면 됩니다 (가드는 감시를 시작합니다).")
        asyncio.ensure_future(self.stdin_loop())
        print("명령: load <시나리오> [demo|rehearsal] / start / g / g! / auto on|off / h(전체 HOLD) / r(재개) / s(상태) / q(종료)")
        print(f"자동 진행: {'켜짐' if self.auto else '꺼짐'} — 4대 도착 {C.AUTO_SYNC_DELAY:.0f}초 후 자동으로 다음 기동, 착륙 {'자동' if C.AUTO_LAND else '수동 g'}\n")
        period = 1.0 / C.LOOP_HZ
        k = 0
        self.last_tick_real = time.monotonic()
        self.loop_running = True
        try:
            while not self.quit:
                t0 = time.monotonic()
                self.last_tick_real = time.monotonic()
                try:
                    self.tick(k)
                except Exception:
                    self.tick_errors += 1
                    self.event("SYS", "※ 가드 내부 오류 → 회피 중 기체 HOLD")
                    traceback.print_exc()
                    for d in self.ds:
                        if self.core.own[d.id].owned:
                            self.core.own[d.id].owned = False
                            asyncio.ensure_future(d.sys.action.hold())
                k += 1
                await asyncio.sleep(max(0.0, period - (time.monotonic() - t0)))
        finally:
            await self.shutdown()

    def tick(self, k):
        t = self.now()
        self.auto_tick(t)
        ins = []
        goals = {}
        for d in self.ds:
            if d.connected and d.total and d.total != len(d.items) and not d.reloading:
                d.reloading = True
                asyncio.ensure_future(self.download_mission(d))
            if d.lat is None or self.frame is None:
                continue
            f, r = self.fr(d.lat, d.lon)
            vf, vr = self.v_fr(d.vn, d.ve)
            age = t - d.t_pos
            if d.in_air:
                d.max_gap = max(d.max_gap, age)
                if d.batt is not None and d.batt < C.BATT_WARN and not d.batt_warned:
                    d.batt_warned = True
                    self.event(d.id, f"※ 배터리 {d.batt:.0f}% — 이번 기동 후 착륙 권장 (h → QGC RTL)")
            it, prev = self.goal_of(d)
            g = self._item_fr(it) if it is not None else None
            goals[d.id] = (it, prev)
            ghold = it is not None and (it.command in (17, 19) or (it.command == 16 and it.param1 > 0))
            ins.append(DroneIn(d.id, d.prio, age < C.STALE_T, age, f, r, d.abs_alt, vf, vr, -d.vd,
                               d.rel_alt, d.in_air, d.mode, g, d.cfg["layer"], ghold,
                               (it.z if it is not None else None),
                               (self.fr(*d.home) if getattr(d, "home", None) else None)))
            # 경로 추종 오차 (가드 개입 중이 아닐 때, 5 m 이상 직선 구간)
            if it is not None and prev is not None and d.mode == "MISSION" and not self.core.own[d.id].owned \
                    and t - d.t_release > 10.0:
                af, ar = self._item_fr(prev)
                bf, br = g
                lf, lr = bf - af, br - ar
                L = math.hypot(lf, lr)
                if L > 5.0:
                    s = ((f - af) * lf + (r - ar) * lr) / (L * L)
                    if 0.1 < s < 0.9:
                        xt = abs((f - af) * lr - (r - ar) * lf) / L
                        d.xt_max = max(d.xt_max, xt)
                        d.xt_sq += xt * xt
                        d.xt_n += 1
        # 안전망: 가드가 잡고 있지 않은데 Offboard 인 기체 (경합·버그 등) → 1초 지나면 정지 후 HOLD
        for d in self.ds:
            if d.connected and d.in_air and d.mode == "OFFBOARD" and not self.core.own[d.id].owned and not d.busy:
                if d.orphan_since is None:
                    d.orphan_since = t
                elif t - d.orphan_since > 1.0:
                    d.orphan_since = t + 2.0      # 재시도 간격
                    self.event(d.id, "※ 가드 미관리 Offboard 감지 → 정지·HOLD")
                    asyncio.ensure_future(self._stop_hold(d))
            else:
                d.orphan_since = None
        by = {d.id: d for d in self.ds}
        for kind, did, val in self.core.step(t, ins):
            if kind == "event":
                self.event(did, val)
                continue
            d = by[did]
            if kind == "takeover":
                if not d.busy:
                    asyncio.ensure_future(self.takeover(d, val))
            elif kind == "vel":
                if not d.busy:
                    asyncio.ensure_future(self.set_vel(d, val))
            elif kind == "release":
                d.t_release = t
                asyncio.ensure_future(self.release(d))
        # 로그 10 Hz, 화면 5 Hz
        if k % 2 == 0:
            self.write_log(t, ins)
        if k % 4 == 0:
            self.send_map(t, ins)
            self.gcs.send(t, ins)
        if k % 2 == 0:
            for cmd in self.gcs.poll():
                self.event("GCS", f"GCS 명령: {cmd}")
                self.dispatch(cmd)

    def write_log(self, t, ins):
        row = [f"{t:.2f}"]
        by = {x.id: x for x in ins}
        for d in self.ds:
            x = by.get(d.id)
            if x is None:
                row += [""] * 9
            else:
                row += [x.mode, f"{x.f:.2f}", f"{x.r:.2f}", f"{x.rel_alt:.2f}", f"{x.vf:.2f}", f"{x.vr:.2f}",
                        int(self.core.own[d.id].owned), int(x.fresh), d.cur]
        mp, md = "", ""
        if self.core.pairs:
            k, pe = min(self.core.pairs.items(), key=lambda kv: math.hypot(kv[1].d_now, kv[1].dz))
            mp, md = f"{k[0]}-{k[1]}", f"{math.hypot(pe.d_now, pe.dz):.2f}"
        row += [mp, md]
        self.log.writerow(row)

    def send_map(self, t, ins):
        msg = {"t": t, "drones": [], "pairs": [], "events": self.events_recent,
               "min_sep": {f"{a}-{b}": v for (a, b), v in self.core.min_sep.items()},
               "geom": {"home_line": C.HOME_LINE_F, "radius": C.SCENARIO_RADIUS, "d_safe": C.D_SAFE}}
        for x in ins:
            o = self.core.own[x.id]
            msg["drones"].append({"id": x.id, "f": x.f, "r": x.r, "alt": x.rel_alt, "vf": x.vf, "vr": x.vr,
                                  "mode": x.mode, "own": o.owned, "yield": o.yielding, "fresh": x.fresh,
                                  "goal": x.goal})
        for (a, b), pe in self.core.pairs.items():
            if pe.level or pe.d_now < C.D_SAFE + C.RELEASE_MARGIN + 4:
                msg["pairs"].append({"a": a, "b": b, "d": pe.d_now, "dz": pe.dz, "level": pe.level})
        try:
            self.sock.sendto(json.dumps(msg).encode(), C.MAP_UDP)
        except Exception:
            pass

    async def shutdown(self):
        if self._shut:
            return
        self._shut = True
        self.loop_running = False
        for d in self.ds:
            if self.core.own[d.id].owned and d.connected:
                try:
                    await d.sys.action.hold()
                    self.event(d.id, "종료: 가드 개입 중이던 기체 HOLD")
                except Exception:
                    pass
        self.write_summary()
        self.logf.close()
        self.evf.close()
        self.quit = True
        if self.servers:
            self.servers.stop()

    def write_summary(self):
        lines = ["ACACT Guard 결과 요약", "=" * 40]
        lines.append(f"기록: {self.log_path}")
        lines.append("\n[기체 간 최소 거리]  (같은 층 = 고도차 %.0f m 이내일 때의 수평거리)" % C.V_SEP)
        for (a, b), v in sorted(self.core.min_sep.items()):
            v3 = self.core.min_3d.get((a, b), float("nan"))
            lines.append(f"  {a}-{b}: 같은 층 {v:5.1f} m / 3D {v3:5.1f} m  {'OK' if v >= 5.0 else '※ 5 m 미만'}")
        lines.append("\n[가드 개입]")
        for d in self.ds:
            o = self.core.own[d.id]
            rms = math.sqrt(d.xt_sq / d.xt_n) if d.xt_n else float("nan")
            lines.append(f"  {d.id}: 개입 {o.takeovers}회, 개입 시간 {o.owned_time:5.1f} s, "
                         f"경로추종 오차 최대 {d.xt_max:4.1f} m / RMS {rms:4.1f} m (회피 후 10초 제외)")
        lines.append("\n[링크 품질]  (국내 실기에서 반드시 확인: 수신 공백 < 0.5 s, 전환 지연 < 0.7 s 권장)")
        for d in self.ds:
            sl = d.switch_lat
            sw = f"{max(sl):.2f} s (평균 {sum(sl) / len(sl):.2f})" if sl else "-"
            lines.append(f"  {d.id}: 비행 중 최대 수신 공백 {d.max_gap:4.2f} s, Offboard 전환 지연 최대 {sw}")
        txt = "\n".join(lines)
        print("\n" + txt)
        with open(self.sum_path, "w", encoding="utf-8") as f:
            f.write(txt + "\n")


def main():
    ap = argparse.ArgumentParser(description="ACACT 충돌 가드")
    ap.add_argument("--drones", default=None, help="일부 기체만 (예: D1,D3). 생략 시 4대")
    ap.add_argument("--host", default="127.0.0.1", help="mavsdk_server 주소")
    ap.add_argument("--site", default=None, help="site.json 경로 (기본 plans/site.json)")
    ap.add_argument("--no-spawn", action="store_true",
                    help="mavsdk_server 를 직접 띄워 둔 경우 (권장하지 않음: 가드 종료 시 setpoint 가 계속 나감)")
    args = ap.parse_args()
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    g = Guard(args)
    try:
        loop.run_until_complete(g.run())
    except KeyboardInterrupt:
        loop.run_until_complete(g.shutdown())


if __name__ == "__main__":
    main()
