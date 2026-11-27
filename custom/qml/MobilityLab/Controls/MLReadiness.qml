pragma Singleton

import QtQuick

import QGroundControl

// Flight readiness of one vehicle, shared by the integrated pre-flight check (MLPreflightView),
// the STANDARD readiness panel and the fleet cards. Values come from the vehicle telemetry (QGC),
// the user-mission check and ACACT's own pre-flight check (both passed in from mlGuard).
//   status: 2 pass · 1 caution · 0 fail · -1 no data
QtObject {
    function fv(f) { if (!f) return NaN; var v = f.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
    function acactFor(pf, sysid) { if (!pf) return null; for (var i = 0; i < pf.length; i++) if (Number(pf[i].sysid) === Number(sysid)) return pf[i]; return null }
    function missionFor(mc, sysid) {
        var vs = mc && mc.vehicles ? mc.vehicles : []
        for (var i = 0; i < vs.length; i++) if (Number(vs[i].sysid) === Number(sysid)) return vs[i]
        return null
    }

    // the seven checks of the integrated pre-flight check (unchanged from v1.0)
    function checks(v, pf, mc, hasGuard) {
        var r = []
        var lost = v.vehicleLinkManager.communicationLost
        var rssi = fv(v.radioStatus.lrssi)
        r.push({ key: "link", k: qsTr("통신 링크"), s: lost ? 0 : 2, d: lost ? qsTr("텔레메트리 두절") : (isNaN(rssi) || rssi === 0 ? qsTr("수신 정상") : qsTr("수신 %1 dBm").arg(rssi.toFixed(0))),
                 why: qsTr("기체와 통신이 끊겼습니다. 텔레메트리 모뎀과 안테나를 확인하세요.") })
        var lock = fv(v.gps.lock), sats = fv(v.gps.count), hdop = fv(v.gps.hdop)
        var gs = isNaN(lock) ? -1 : (lock < 3 ? 0 : ((sats < 10 || hdop > 2.0) ? 1 : 2))
        r.push({ key: "gnss", k: "GNSS", s: gs, d: isNaN(lock) ? qsTr("데이터 없음") : ((lock >= 6 ? "RTK FIX" : (lock === 5 ? "RTK FLOAT" : (lock >= 3 ? "3D FIX" : "NO FIX"))) + qsTr(" · 위성 %1 · HDOP %2").arg(isNaN(sats) ? "—" : sats).arg(isNaN(hdop) ? "—" : hdop.toFixed(1))),
                 why: gs === 0 ? qsTr("GPS 위치를 아직 잡지 못했습니다. 하늘이 트인 곳에서 잠시 기다리세요.") : qsTr("GPS 위성 수가 적거나 정밀도(HDOP)가 낮습니다.") })
        var bat = v.batteries.count > 0 ? v.batteries.get(0) : null
        var pct = bat ? fv(bat.percentRemaining) : NaN, volt = bat ? fv(bat.voltage) : NaN
        r.push({ key: "batt", k: qsTr("배터리"), s: isNaN(pct) ? -1 : (pct < 30 ? 0 : (pct < 80 ? 1 : 2)), d: isNaN(pct) ? qsTr("데이터 없음") : pct.toFixed(0) + "%" + (isNaN(volt) ? "" : " · " + volt.toFixed(1) + " V") + (pct < 80 ? qsTr(" (ACACT 시험 기준 80% 이상)") : ""),
                 why: isNaN(pct) ? qsTr("배터리 정보를 받지 못했습니다.") : (pct < 30 ? qsTr("배터리가 %1%로 부족합니다. 충전된 배터리로 바꾸세요.").arg(pct.toFixed(0)) : qsTr("배터리가 %1%입니다. ACACT 시험 기준은 80% 이상입니다.").arg(pct.toFixed(0))) })
        var ready = v.readyToFlyAvailable ? v.readyToFly : true
        var unhealthy = v.sensorsUnhealthyBits !== undefined ? v.sensorsUnhealthyBits : 0
        r.push({ key: "health", k: qsTr("기체 상태"), s: unhealthy !== 0 ? 0 : (!ready ? 1 : 2), d: unhealthy !== 0 ? qsTr("센서 이상 보고됨 — 기체 설정에서 확인") : (!ready ? qsTr("비행 준비 안 됨 (FC 점검 미통과)") : (v.armed ? qsTr("시동 걸림") : qsTr("정상 · 시동 대기"))),
                 why: unhealthy !== 0 ? qsTr("비행 컨트롤러가 센서 이상을 보고했습니다. 기체 설정 › 센서에서 확인하세요.") : qsTr("비행 컨트롤러 자체 점검을 아직 통과하지 못했습니다. 위쪽 상태 표시를 눌러 사유를 확인하세요.") })
        var fw = MLTheme.fwInfo(v)
        r.push({ key: "fw", k: qsTr("펌웨어 · 모드"), s: !fw.ok || fw.modeUnknown ? 1 : 2, d: fw.name + (fw.known ? " " + fw.version : "") + " · " + v.flightMode + (!fw.ok ? qsTr(" (권장 %1 이상)").arg(fw.recommend) : ""),
                 why: fw.modeUnknown ? qsTr("비행 모드를 인식하지 못했습니다. 펌웨어 종류를 확인하세요.") : qsTr("펌웨어가 검증된 버전(%1)보다 낮습니다.").arg(fw.recommend) })
        var m = missionFor(mc, v.id)
        var errs = 0, warns = 0, first = ""
        if (m && m.issues) for (var i = 0; i < m.issues.length; i++) {
            if (m.issues[i].level >= 2) { errs++; if (first === "") first = m.issues[i].text || "" }
            else if (m.issues[i].level === 1) warns++
        }
        r.push({ key: "mission", k: qsTr("미션"), s: !m ? -1 : (m.navItems === 0 ? 0 : (errs > 0 ? 0 : (warns > 0 ? 1 : 2))),
                 d: !m ? qsTr("미션 검사 전") : (m.navItems === 0 ? qsTr("미션 없음") : qsTr("%1 km · %2 · 최고 %3 m").arg((m.length / 1000).toFixed(2)).arg(MLTheme.duration(m.duration)).arg(Number(m.maxAlt).toFixed(0)) + (errs ? qsTr(" · 오류 %1").arg(errs) : "") + (warns ? qsTr(" · 주의 %1").arg(warns) : "")),
                 why: !m ? qsTr("미션 검사를 아직 하지 않았습니다.") : (m.navItems === 0 ? qsTr("기체에 미션이 없습니다. 미션을 만들고 업로드하세요.") : (errs > 0 ? (first !== "" ? first : qsTr("미션에 오류가 있습니다. 미션 검사 결과를 확인하세요.")) : qsTr("미션에 주의 항목이 있습니다."))) })
        var a = acactFor(pf, v.id)
        r.push({ key: "acact", k: "ACACT", s: !hasGuard ? -1 : (!a ? -1 : (a.ok ? 2 : 0)), d: !a ? qsTr("점검 실행을 누르세요") : (a.ok ? qsTr("준비 완료") : a.issues.join(" · ")),
                 why: !a ? qsTr("ACACT 사전 점검을 아직 실행하지 않았습니다.") : (a.issues ? a.issues.join(" · ") : "") })
        return r
    }

    // overall: go (no fail), level 2 / 1 / 0, and the plain-language reasons the vehicle cannot fly yet
    function summary(v, pf, mc, hasGuard) {
        var c = checks(v, pf, mc, hasGuard)
        var lvl = 2, reasons = [], notes = []
        for (var i = 0; i < c.length; i++) {
            var s = c[i].s
            if (s === 0) { lvl = 0; reasons.push(c[i].why) }
            else if (s === 1 || s === -1) { if (lvl > 1) lvl = 1; notes.push(c[i].why) }
        }
        return { go: lvl > 0, level: lvl, reasons: reasons, notes: notes, checks: c }
    }
}
