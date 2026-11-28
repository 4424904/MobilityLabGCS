import QtQuick
import QtQuick.Controls

import QGroundControl

// 통합 경고 센터: every abnormal condition in one list, ordered by risk, each with its cause and
// what the operator should check. Conditions are evaluated continuously from telemetry, ACACT and
// the map service; an alert leaves the list when its condition clears. Acknowledging only dims it
// (until it gets worse) — it never hides a warning that is still true.
//
// Also used headless by the top bar for the bell count (alerts / unacked / worst).
Item {
    id: root
    readonly property real u: MLTheme.u
    readonly property var  _vs: QGroundControl.multiVehicleManager.vehicles
    readonly property bool _g:  typeof mlGuard !== "undefined"
    property var acked: ({})            // key → level acknowledged
    property int _tick: 0
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: {
            root._tick++
            // forget acknowledgements of conditions that have cleared, so a new occurrence alerts again
            var keep = ({}), changed = false
            for (var i = 0; i < root.alerts.length; i++) if (root.acked[root.alerts[i].key] !== undefined) keep[root.alerts[i].key] = root.acked[root.alerts[i].key]
            for (var k in root.acked) if (keep[k] === undefined) changed = true
            if (changed) root.acked = keep
        }
    }

    function fv(f) { if (!f) return NaN; var v = f.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
    // level (v1.2): 4 긴급 emergency · 3 위험 warning · 2 주의 caution · 1 정보 advisory
    // 긴급 = act now or lose the aircraft / a collision: link lost in flight, critical battery in
    // flight, no position fix in flight, two vehicles inside the emergency distance
    readonly property var alerts: {
        _tick
        var a = []
        function add(key, level, vid, title, cause, action) { a.push({ key: key, level: level, vid: vid, title: title, cause: cause, action: action }) }
        var flying = 0
        for (var i = 0; i < _vs.count; i++) {
            var v = _vs.get(i), id = v.id, n = MLTheme.uavName(id)
            if (v.flying) flying++
            if (v.vehicleLinkManager.communicationLost)
                add("link" + id, v.flying ? 4 : 3, id, qsTr("%1 통신 두절").arg(n), qsTr("텔레메트리 수신 없음 — FC 페일세이프(RTL/LAND/HOLD)가 동작할 수 있습니다"), qsTr("링크·안테나·모뎀 전원 확인, 기체 육안 확인, 필요 시 조종기 수동 전환"))
            var bat = v.batteries.count > 0 ? v.batteries.get(0) : null
            var pct = bat ? fv(bat.percentRemaining) : NaN
            if (!isNaN(pct) && pct < 15) add("bat" + id, v.flying ? 4 : 3, id, qsTr("%1 배터리 위험 %2%").arg(n).arg(pct.toFixed(0)), qsTr("잔량 15% 미만"), qsTr("즉시 귀환(RTL) 또는 착륙"))
            else if (!isNaN(pct) && pct < 30 && v.flying) add("bat" + id, 2, id, qsTr("%1 배터리 부족 %2%").arg(n).arg(pct.toFixed(0)), qsTr("잔량 30% 미만"), qsTr("남은 미션 시간 확인, 귀환 준비"))
            var lock = fv(v.gps.lock), hdop = fv(v.gps.hdop)
            if (!isNaN(lock) && lock > 0 && lock < 3) add("gps" + id, v.flying ? 4 : 2, id, qsTr("%1 GNSS 위치 불량").arg(n), qsTr("3D 고정 아님 (fix %1)").arg(lock), qsTr("위치 기반 비행·ACACT 회피 불가 — 수동 조종 대비"))
            else if (!isNaN(hdop) && hdop > 2.5) add("hdop" + id, 1, id, qsTr("%1 GNSS 정확도 저하").arg(n), qsTr("HDOP %1").arg(hdop.toFixed(1)), qsTr("위성 상태 확인, 주변 차폐물 확인"))
            if (v.sensorsUnhealthyBits !== 0) add("sens" + id, v.flying ? 3 : 2, id, qsTr("%1 센서 이상").arg(n), qsTr("FC가 비정상 센서를 보고함"), qsTr("기체 설정 › 센서 확인, 비행 중이면 착륙 고려"))
        }
        if (_g) {
            var ds = mlGuard.drones
            for (var k = 0; k < ds.length; k++) {
                var d = ds[k]
                if (d.phase === "avoid") add("avoid" + d.id, 3, d.sysid, qsTr("%1 ACACT 회피 기동 중").arg(d.id), d.reason || qsTr("충돌 위험"), qsTr("기체 움직임 감시 — 조종기 개입 시 가드가 제어권을 넘김"))
                else if (d.phase === "operator") add("lock" + d.id, 2, d.sysid, qsTr("%1 운용자 제어 중").arg(d.id), qsTr("비행 모드가 바뀌어 ACACT가 이 기체에서 손을 뗌"), qsTr("미션 재개(MISSION) 시 다시 감시"))
                else if (d.phase === "lost" && mlGuard.active) add("glost" + d.id, 3, d.sysid, qsTr("%1 ACACT 텔레메트리 두절").arg(d.id), qsTr("가드가 위치를 받지 못함 — 다른 기체는 이 기체를 예측 위치로 피함"), qsTr("링크 확인 · PX4 Offboard 상실 페일세이프 확인"))
            }
            var ps = mlGuard.pairs
            for (var j = 0; j < ps.length; j++) {
                var p = ps[j]
                if (p.level >= 2) add("pair" + p.a + p.b, 4, 0, qsTr("%1·%2 비상 근접 %3 m").arg(p.a).arg(p.b).arg(p.d.toFixed(1)), qsTr("비상 이격 이내"), qsTr("회피 진행 확인 — 필요 시 전체 HOLD"))
                else if (p.level === 1) add("pair" + p.a + p.b, 2, 0, qsTr("%1·%2 충돌 예측").arg(p.a).arg(p.b), qsTr("%1초 후 최소 %2 m 예측").arg(p.tcpa.toFixed(1)).arg(p.cpa.toFixed(1)), qsTr("ACACT 회피 개입 확인"))
            }
            if (!mlGuard.active && flying >= 2) add("guardoff", 2, 0, qsTr("다기체 비행 중 ACACT 꺼짐"), qsTr("%1기 비행 중, 충돌 회피 감시 없음").arg(flying), qsTr("ACACT 콘솔에서 가드 시작 또는 고도 분리 확인"))
            if (mlGuard.opModeProblem !== "") add("opmode", 2, 0, qsTr("운용 모드 불일치"), mlGuard.opModeProblem, qsTr("설정 › 운용 모드 확인 (SITL / 실기체)"))
        }
        if (typeof mlMap !== "undefined" && mlMap.status === "error") add("map", 1, 0, qsTr("지도 표시 불가"), mlMap.statusText, qsTr("지도 도구 › 지도 공급자에서 대체 지도 선택"))
        a.sort(function(x, y) { return y.level - x.level })
        return a
    }
    readonly property int worst: alerts.length ? alerts[0].level : 0
    readonly property int unacked: {
        var n = 0
        for (var i = 0; i < alerts.length; i++) if (!(acked[alerts[i].key] >= alerts[i].level)) n++
        return n
    }
    // ---- v1.2: raise / clear tracking, history, record, voice --------------------------------------
    property var _open: ({})                         // key → {level, title, vid, raised}
    property ListModel history: ListModel {}         // newest first: key level title vid raised cleared action
    readonly property var levelNames: ["", qsTr("정보"), qsTr("주의"), qsTr("위험"), qsTr("긴급")]
    readonly property var levelIcons: ["", "i", "!", "▲", "⛔"]
    property var _spoken: ({})                        // key → ms of the last announcement
    function _now() { return Qt.formatTime(new Date(), "HH:mm:ss") }
    function _rec(level, text, vid) { if (typeof mlRecords !== "undefined") mlRecords.event(level, "ALERT", text, vid) }
    function _say(a) {
        if (!MLState.voiceAlerts || a.level < MLState.voiceMinLevel || typeof mlUi === "undefined") return
        var t = Date.now()
        if (_spoken[a.key] && t - _spoken[a.key] < 30000) return     // the same alert at most every 30 s
        _spoken[a.key] = t
        mlUi.say(levelNames[a.level] + ". " + a.title)
    }
    onAlertsChanged: {
        var seen = ({}), open = Object.assign({}, _open)
        for (var i = 0; i < alerts.length; i++) {
            var a = alerts[i]
            seen[a.key] = true
            var o = open[a.key]
            if (!o || a.level > o.level) {
                open[a.key] = { level: a.level, title: a.title, vid: a.vid, raised: o ? o.raised : _now() }
                history.insert(0, { key: a.key, level: a.level, title: a.title, vid: a.vid, raised: _now(), cleared: "", action: a.action })
                if (history.count > 300) history.remove(300, history.count - 300)
                _rec(a.level, qsTr("발생 · %1 — %2").arg(a.title).arg(a.cause), a.vid)
                _say(a)
            } else if (a.level < o.level) {
                open[a.key].level = a.level
            }
        }
        for (var k in open) {
            if (seen[k]) continue
            for (var j = 0; j < history.count; j++) if (history.get(j).key === k && history.get(j).cleared === "") { history.setProperty(j, "cleared", _now()); break }
            _rec(0, qsTr("해제 · %1").arg(open[k].title), open[k].vid)
            delete open[k]
        }
        _open = open
    }

    function ack(key, level) { var c = Object.assign({}, acked); c[key] = level; acked = c }
    function ackAll() { var c = ({}); for (var i = 0; i < alerts.length; i++) c[alerts[i].key] = alerts[i].level; acked = c }
}
