import QtQuick

import QGroundControl
import QGroundControl.Controls

// 경고 (crew alerting): powertrain alerts from TandemTelemetry plus what any
// airframe can raise (link lost, battery, GPS), most severe first.
// New alerts are highlighted until acknowledged with [확인].
Column {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property real u:           MLTheme.u
    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property bool _commLost:   !!vehicle && vehicle.vehicleLinkManager.communicationLost

    function _v(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined) ? NaN : v }

    readonly property var _generic: {
        var list = []
        if (!vehicle) return list
        if (_commLost) list.push({ level: 3, text: qsTr("통신 두절"), time: "", acked: true })
        var bats = vehicle.batteries
        for (var i = 0; bats && i < bats.count; i++) {
            var b = bats.get(i)
            if (!b) continue
            var state = _v(b.chargeState), pct = _v(b.percentRemaining)
            var name = bats.count > 1 ? qsTr("배터리 %1").arg(_v(b.id) + 1) : qsTr("배터리")
            if (state >= 3 || (!isNaN(pct) && pct < 15))      list.push({ level: 3, text: qsTr("%1 잔량 위험").arg(name), time: "", acked: true })
            else if (state === 2 || (!isNaN(pct) && pct < 30)) list.push({ level: 2, text: qsTr("%1 잔량 낮음").arg(name), time: "", acked: true })
        }
        var fw = MLTheme.fwInfo(vehicle)
        if (fw.modeUnknown && !_commLost) list.push({ level: 2, text: qsTr("비행 모드 인식 불가 · 펌웨어 확인"), time: "", acked: true })
        else if (fw.known && !fw.ok)      list.push({ level: 2, text: qsTr("%1 %2 · 권장 %3 이상").arg(fw.name).arg(fw.version).arg(fw.recommend), time: "", acked: true })
        var lock = _v(vehicle.gps.lock)
        if (vehicle.armed && !isNaN(lock) && lock < 3) list.push({ level: vehicle.flying ? 3 : 2, text: qsTr("GPS 위치 고정 안 됨"), time: "", acked: true })
        return list
    }
    readonly property var _alerts: {
        var all = _generic.concat(_t ? _t.alerts : [])
        all.sort(function(a, b) { return b.level - a.level })
        return all
    }
    readonly property int _warn: _alerts.filter(function(a) { return a.level === 3 }).length
    readonly property int _caut: _alerts.filter(function(a) { return a.level === 2 }).length
    readonly property bool _unacked: !!_t && (_t.masterWarning || _t.masterCaution)

    Item {
        width:  root.width
        height: 38 * u
        Rectangle { width: parent.width; height: 1; color: MLTheme.line }
        MLText {
            x: 20 * u; anchors.bottom: parent.bottom; anchors.bottomMargin: 8 * u
            text: qsTr("경고"); color: MLTheme.label; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; font.letterSpacing: 1.4 * u
        }
        Row {
            anchors.right: parent.right; anchors.rightMargin: 20 * u; anchors.bottom: parent.bottom; anchors.bottomMargin: 6 * u
            spacing: 10 * u
            Text { visible: root._warn > 0; text: "WARNING " + root._warn; color: MLTheme.warning; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: root._caut > 0; text: "CAUTION " + root._caut; color: MLTheme.caution; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
            Text { visible: root._alerts.length === 0; text: root.vehicle ? qsTr("정상") : "—"; color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
            Rectangle {
                visible:    root._unacked
                width:      ackText.implicitWidth + 16 * u
                height:     22 * u
                radius:     3 * u
                color:      ackMouse.containsMouse ? "#2A2112" : "transparent"
                border.width: 1
                border.color: root._t && root._t.masterWarning ? MLTheme.warning : MLTheme.caution
                MLText { id: ackText; anchors.centerIn: parent; text: qsTr("확인"); font.pixelSize: MLTheme.fsLabel; color: parent.border.color }
                MouseArea { id: ackMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: if (root._t) root._t.acknowledgeAll() }
                SequentialAnimation on opacity { running: root._unacked; loops: Animation.Infinite; NumberAnimation { to: 0.35; duration: 450 } NumberAnimation { to: 1; duration: 450 } }
            }
        }
    }

    Repeater {
        model: Math.min(6, root._alerts.length)
        Rectangle {
            readonly property var a: root._alerts[index] || ({ level: 0, text: "", time: "", acked: true })
            readonly property color _c: a.level === 3 ? MLTheme.warning : MLTheme.caution
            width:  root.width
            height: 28 * u
            color:  a.acked ? "transparent" : (a.level === 3 ? "#2A1213" : "#211A0C")
            Rectangle { x: 20 * u; width: 2 * u; height: parent.height - 10 * u; anchors.verticalCenter: parent.verticalCenter; color: parent._c }
            MLText { x: 30 * u; width: parent.width - 130 * u; anchors.verticalCenter: parent.verticalCenter; text: parent.a.text; color: parent._c; font.pixelSize: MLTheme.fsBody }
            Text { anchors.right: parent.right; anchors.rightMargin: 20 * u; anchors.verticalCenter: parent.verticalCenter; text: parent.a.time || ""; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
        }
    }
    Item {
        visible:    root._alerts.length === 0
        width:      root.width
        height:     30 * u
        MLText { x: 20 * u; anchors.verticalCenter: parent.verticalCenter; text: root.vehicle ? qsTr("활성 경고 없음") : qsTr("기체 연결 대기"); color: MLTheme.faint; font.pixelSize: MLTheme.fsBody }
    }
    Text {
        visible:    root._alerts.length > 6
        x:          20 * u
        text:       qsTr("외 %1건").arg(root._alerts.length - 6)
        color:      MLTheme.dim
        font.family: MLTheme.sans
        font.pixelSize: MLTheme.fsLabel
    }
    Item { width: 1; height: 8 * u }
}
