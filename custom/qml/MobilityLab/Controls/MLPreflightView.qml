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

    // the checks themselves live in MLReadiness (shared with the STANDARD readiness panel)
    function checks(v) { return MLReadiness.checks(v, _pf, _mc, _g) }
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
