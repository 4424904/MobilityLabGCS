import QtQuick
import QtQuick.Controls

import QGroundControl

// 비행 전 통합 점검: one column per connected vehicle, the same seven checks for each, and an
// overall GO / NO-GO. Values come from the vehicle telemetry (QGC), the user-mission check and
// ACACT's own pre-flight check (mlGuard.runPreflight). "점검 실행" refreshes the ACACT part.
//   통신 · GNSS · 배터리 · 기체 상태 · 펌웨어/모드 · 미션 · ACACT
Rectangle {
    id: root
    signal closeRequested()
    readonly property real u:       MLTheme.u
    readonly property var  _vs:     QGroundControl.multiVehicleManager.vehicles
    readonly property bool _g:      typeof mlGuard !== "undefined"
    readonly property var  _pf:     _g ? mlGuard.preflight : []
    readonly property var  _mc:     _g ? mlGuard.missionCheck : ({})

    color:          MLTheme.panelSolid
    radius:         MLTheme.panelRadius
    border.color:   MLTheme.lineStrong

    function fv(f) { if (!f) return NaN; var v = f.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
    function acactFor(sysid) { for (var i = 0; i < _pf.length; i++) if (Number(_pf[i].sysid) === Number(sysid)) return _pf[i]; return null }
    function missionFor(sysid) {
        var vs = _mc && _mc.vehicles ? _mc.vehicles : []
        for (var i = 0; i < vs.length; i++) if (Number(vs[i].sysid) === Number(sysid)) return vs[i]
        return null
    }
    // status: 2 pass · 1 caution · 0 fail · -1 no data
    function checks(v) {
        var r = []
        var lost = v.vehicleLinkManager.communicationLost
        var rssi = fv(v.radioStatus.lrssi)
        r.push({ k: qsTr("통신 링크"), s: lost ? 0 : 2, d: lost ? qsTr("텔레메트리 두절") : (isNaN(rssi) || rssi === 0 ? qsTr("수신 정상") : qsTr("수신 %1 dBm").arg(rssi.toFixed(0))) })
        var lock = fv(v.gps.lock), sats = fv(v.gps.count), hdop = fv(v.gps.hdop)
        var gs = isNaN(lock) ? -1 : (lock < 3 ? 0 : ((sats < 10 || hdop > 2.0) ? 1 : 2))
        r.push({ k: "GNSS", s: gs, d: isNaN(lock) ? qsTr("데이터 없음") : ((lock >= 6 ? "RTK FIX" : (lock === 5 ? "RTK FLOAT" : (lock >= 3 ? "3D FIX" : "NO FIX"))) + qsTr(" · 위성 %1 · HDOP %2").arg(isNaN(sats) ? "—" : sats).arg(isNaN(hdop) ? "—" : hdop.toFixed(1))) })
        var bat = v.batteries.count > 0 ? v.batteries.get(0) : null
        var pct = bat ? fv(bat.percentRemaining) : NaN, volt = bat ? fv(bat.voltage) : NaN
        r.push({ k: qsTr("배터리"), s: isNaN(pct) ? -1 : (pct < 30 ? 0 : (pct < 80 ? 1 : 2)), d: isNaN(pct) ? qsTr("데이터 없음") : pct.toFixed(0) + "%" + (isNaN(volt) ? "" : " · " + volt.toFixed(1) + " V") + (pct < 80 ? qsTr(" (ACACT 시험 기준 80% 이상)") : "") })
        var ready = v.readyToFlyAvailable ? v.readyToFly : true
        var unhealthy = v.sensorsUnhealthyBits !== undefined ? v.sensorsUnhealthyBits : 0
        r.push({ k: qsTr("기체 상태"), s: unhealthy !== 0 ? 0 : (!ready ? 1 : 2), d: unhealthy !== 0 ? qsTr("센서 이상 보고됨 — 기체 설정에서 확인") : (!ready ? qsTr("비행 준비 안 됨 (FC 점검 미통과)") : (v.armed ? qsTr("시동 걸림") : qsTr("정상 · 시동 대기"))) })
        var fw = MLTheme.fwInfo(v)
        r.push({ k: qsTr("펌웨어 · 모드"), s: !fw.ok || fw.modeUnknown ? 1 : 2, d: fw.name + (fw.known ? " " + fw.version : "") + " · " + v.flightMode + (!fw.ok ? qsTr(" (권장 %1 이상)").arg(fw.recommend) : "") })
        var m = missionFor(v.id)
        var errs = 0, warns = 0
        if (m && m.issues) for (var i = 0; i < m.issues.length; i++) { if (m.issues[i].level >= 2) errs++; else if (m.issues[i].level === 1) warns++ }
        r.push({ k: qsTr("미션"), s: !m ? -1 : (m.navItems === 0 ? 0 : (errs > 0 ? 0 : (warns > 0 ? 1 : 2))),
                 d: !m ? qsTr("미션 검사 전") : (m.navItems === 0 ? qsTr("미션 없음") : qsTr("%1 km · %2 · 최고 %3 m").arg((m.length / 1000).toFixed(2)).arg(MLTheme.duration(m.duration)).arg(Number(m.maxAlt).toFixed(0)) + (errs ? qsTr(" · 오류 %1").arg(errs) : "") + (warns ? qsTr(" · 주의 %1").arg(warns) : "")) })
        var a = acactFor(v.id)
        r.push({ k: "ACACT", s: !root._g ? -1 : (!a ? -1 : (a.ok ? 2 : 0)), d: !a ? qsTr("점검 실행을 누르세요") : (a.ok ? qsTr("준비 완료") : a.issues.join(" · ")) })
        return r
    }
    property int _tick: 0
    readonly property var _all: {
        _tick
        var out = []
        for (var i = 0; i < _vs.count; i++) out.push({ v: _vs.get(i), c: checks(_vs.get(i)) })
        return out
    }
    readonly property int _worst: {
        var w = 2
        for (var i = 0; i < _all.length; i++) for (var j = 0; j < _all[i].c.length; j++) w = Math.min(w, _all[i].c[j].s === -1 ? 1 : _all[i].c[j].s)
        return _all.length === 0 ? -1 : w
    }
    Timer { interval: 1000; running: root.visible; repeat: true; onTriggered: root._tick++ }

    // header
    Item {
        id: head
        width: parent.width; height: 64 * u
        Column {
            x: 18 * u; anchors.verticalCenter: parent.verticalCenter
            MLText { text: qsTr("비행 전 통합 점검"); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold }
            MLText { text: qsTr("통신 · GNSS · 배터리 · 기체 · 펌웨어 · 미션 · ACACT — 기체별 판정"); color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel }
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 12 * u; anchors.verticalCenter: parent.verticalCenter
            spacing: 10 * u
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: goText.implicitWidth + 36 * u; height: 40 * u; radius: 8 * u
                readonly property color tone: root._worst < 0 ? MLTheme.dim : (root._worst === 0 ? MLTheme.warning : (root._worst === 1 ? MLTheme.caution : MLTheme.active))
                color: MLTheme.alpha(tone, 0.16); border.color: tone; border.width: 2
                Text { id: goText; anchors.centerIn: parent; color: parent.tone; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsBody; font.weight: Font.Bold
                    text: root._worst < 0 ? qsTr("기체 없음") : (root._worst === 0 ? qsTr("NO-GO · 비행 불가 항목 있음") : (root._worst === 1 ? qsTr("주의 · 확인 후 진행") : qsTr("GO · 모든 항목 정상"))) }
            }
            MLIconButton { label: qsTr("점검 실행"); glyph: "↻"; size: 36 * root.u; enabledState: root._g; onClicked: mlGuard.runPreflight() }
            MLIconButton { glyph: "✕"; size: 36 * root.u; tip: qsTr("닫기"); onClicked: root.closeRequested() }
        }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
    }

    MLText {
        visible: root._vs.count === 0
        anchors.centerIn: parent
        text: qsTr("연결된 기체가 없습니다")
        color: MLTheme.dim
        font.pixelSize: MLTheme.fsTitle
    }

    Flickable {
        anchors.top: head.bottom; anchors.bottom: parent.bottom
        anchors.left: parent.left; anchors.right: parent.right
        anchors.margins: 12 * u
        contentWidth: cols.implicitWidth
        contentHeight: cols.implicitHeight
        clip: true
        ScrollBar.horizontal: ScrollBar {}
        ScrollBar.vertical: ScrollBar {}
        Row {
            id: cols
            spacing: 12 * root.u
            Repeater {
                model: root._all.length
                Rectangle {
                    readonly property var e: root._all[index]
                    readonly property color col: MLTheme.vehicleColor(e.v.id)
                    width: 360 * root.u
                    height: vc.implicitHeight + 20 * root.u
                    radius: 8 * root.u
                    color: MLTheme.tile
                    border.color: MLTheme.line
                    Rectangle { width: parent.width; height: 4 * root.u; radius: 2 * root.u; color: parent.col }
                    Column {
                        id: vc
                        x: 12 * root.u; y: 14 * root.u; width: parent.width - 24 * root.u
                        spacing: 6 * root.u
                        Row {
                            spacing: 8 * root.u
                            Text { text: MLTheme.uavName(e.v.id); color: col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue; font.weight: Font.DemiBold }
                            MLText { text: MLTheme.vehicleTypeName(e.v); color: MLTheme.label; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: MLTheme.fsSmall }
                        }
                        Repeater {
                            model: e.c.length
                            Rectangle {
                                readonly property var c: e.c[index]
                                readonly property color tone: c.s === 2 ? MLTheme.active : (c.s === 1 ? MLTheme.caution : (c.s === 0 ? MLTheme.warning : MLTheme.dim))
                                width: vc.width
                                height: Math.max(44 * root.u, cd.implicitHeight + 14 * root.u)
                                radius: 6 * root.u
                                color: c.s === 0 ? MLTheme.warningFill : (c.s === 1 ? MLTheme.cautionFill : MLTheme.panelRaised)
                                border.color: MLTheme.alpha(tone, 0.5)
                                Text { x: 10 * root.u; anchors.verticalCenter: parent.verticalCenter; text: c.s === 2 ? "✓" : (c.s === 1 ? "!" : (c.s === 0 ? "✕" : "…")); color: tone; font.pixelSize: 18 * root.u; font.weight: Font.Bold; width: 18 * root.u; horizontalAlignment: Text.AlignHCenter }
                                Column {
                                    id: cd
                                    x: 38 * root.u; anchors.verticalCenter: parent.verticalCenter; width: parent.width - 48 * root.u
                                    MLText { text: c.k; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                                    MLText { text: c.d; width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone; color: c.s === 0 ? MLTheme.text : MLTheme.label; font.pixelSize: MLTheme.fsLabel }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
