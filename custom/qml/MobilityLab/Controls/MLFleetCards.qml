import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 편대 · 기체: one status card per connected vehicle (left panel, "다기체" layout).
// Identity colour, link, mode, arming, the five numbers that matter, mission progress and
// what ACACT is doing with the vehicle. Click: select · ◎: centre the map on it.
Item {
    id: root
    readonly property real u:          MLTheme.u
    readonly property var  _vehicles:  QGroundControl.multiVehicleManager.vehicles
    readonly property var  _active:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property bool _g:         typeof mlGuard !== "undefined" && mlGuard.active

    function fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
    function guardDrone(sysid) {
        if (!_g) return null
        var ds = mlGuard.drones
        for (var i = 0; i < ds.length; i++) if (Number(ds[i].sysid) === Number(sysid)) return ds[i]
        return null
    }
    function phaseText(p) {
        switch (p) {
        case "avoid":    return qsTr("회피 기동")
        case "return":   return qsTr("미션 복귀")
        case "operator": return qsTr("운용자 제어")
        case "yield":    return qsTr("양보 대기")
        case "lost":     return qsTr("텔레메트리 두절")
        case "mission":  return qsTr("미션 수행 · 감시")
        case "ground":   return qsTr("지상")
        default:         return qsTr("감시")
        }
    }
    function phaseColor(p) {
        if (p === "avoid" || p === "lost") return MLTheme.warning
        if (p === "return" || p === "operator" || p === "yield") return MLTheme.caution
        if (p === "mission") return MLTheme.active
        return MLTheme.dim
    }

    // ---- summary ---------------------------------------------------------------
    Item {
        id:     head
        width:  parent.width
        height: 52 * u
        readonly property int flying: {
            var n = 0
            for (var i = 0; i < root._vehicles.count; i++) if (root._vehicles.get(i).flying) n++
            return n
        }
        readonly property int lost: {
            var n = 0
            for (var i = 0; i < root._vehicles.count; i++) if (root._vehicles.get(i).vehicleLinkManager.communicationLost) n++
            return n
        }
        Row {
            anchors.left: parent.left; anchors.leftMargin: 14 * u
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18 * u
            Repeater {
                model: [
                    { k: qsTr("연결"), v: root._vehicles.count, c: MLTheme.text },
                    { k: qsTr("비행"), v: head.flying, c: MLTheme.accent },
                    { k: qsTr("두절"), v: head.lost, c: head.lost > 0 ? MLTheme.warning : MLTheme.dim }
                ]
                Column {
                    Text { text: modelData.k; color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                    Text { text: modelData.v; color: modelData.c; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue; font.weight: Font.Medium }
                }
            }
        }
        MLIconButton {
            anchors.right: parent.right; anchors.rightMargin: 10 * u
            anchors.verticalCenter: parent.verticalCenter
            glyph: "⤢"; label: qsTr("전체 보기"); tip: qsTr("모든 기체가 보이도록 지도 맞춤")
            enabledState: root._vehicles.count > 0
            onClicked: MLState.fitAllRequested()
        }
        Rectangle { anchors.bottom: parent.bottom; x: 10 * u; width: parent.width - 20 * u; height: 1; color: MLTheme.line }
    }

    // ---- empty state -------------------------------------------------------------
    Column {
        visible: root._vehicles.count === 0
        anchors.top: head.bottom; anchors.topMargin: 40 * u
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 48 * u
        spacing: 10 * u
        MLWaitIndicator { anchors.horizontalCenter: parent.horizontalCenter }
        MLText { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("기체 연결 대기 중"); font.pixelSize: MLTheme.fsTitle; font.weight: Font.DemiBold }
        MLText {
            width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; elide: Text.ElideNone
            color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall
            text: qsTr("UDP 14550 · 시리얼 텔레메트리를 자동으로 찾고 있습니다. 연결되면 기체마다 카드가 생기고 고유 색상이 지정됩니다.")
        }
    }

    ListView {
        id:             list
        anchors.top:    head.bottom
        anchors.bottom: parent.bottom
        width:          parent.width
        topMargin:      8 * u
        bottomMargin:   8 * u
        spacing:        8 * u
        clip:           true
        model:          root._vehicles
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        delegate: Rectangle {
            id: card
            required property var object
            readonly property var  v:       object
            readonly property bool sel:     v === root._active
            readonly property color col:    MLTheme.vehicleColor(v ? v.id : 1)
            readonly property bool lost:    !!v && v.vehicleLinkManager.communicationLost
            readonly property var  gd:      v ? root.guardDrone(v.id) : null
            readonly property real alt:     v ? root.fv(v.altitudeRelative) : NaN
            readonly property real gs:      v ? root.fv(v.groundSpeed) : NaN
            readonly property real hdg:     v ? root.fv(v.heading) : NaN
            readonly property var  bat:     v && v.batteries.count > 0 ? v.batteries.get(0) : null
            readonly property real pct:     bat ? root.fv(bat.percentRemaining) : NaN
            readonly property real lock:    v ? root.fv(v.gps.lock) : NaN
            readonly property real sats:    v ? root.fv(v.gps.count) : NaN
            readonly property int  cur:     gd ? gd.seq : -1
            readonly property int  total:   gd ? gd.total : 0
            readonly property string phase: gd ? gd.phase : ""

            x: 10 * u
            width: list.width - 20 * u
            height: inner.implicitHeight + 22 * u
            radius: 8 * u
            color: sel ? MLTheme.alpha(col, 0.10) : (cm.containsMouse ? MLTheme.hover : MLTheme.tile)
            border.color: lost ? MLTheme.warning : (sel ? MLTheme.alpha(col, 0.7) : MLTheme.line)
            border.width: lost || sel ? 1.5 : 1
            Behavior on color { ColorAnimation { duration: MLTheme.animFast } }
            Rectangle { x: 0; y: 6 * u; width: 4 * u; height: parent.height - 12 * u; radius: 2 * u; color: card.col }

            MouseArea {
                id: cm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: QGroundControl.multiVehicleManager.activeVehicle = card.v
                onDoubleClicked: if (card.v && card.v.coordinate.isValid) MLState.centerRequested(card.v.coordinate)
            }

            Column {
                id: inner
                x: 16 * u; y: 11 * u
                width: parent.width - 28 * u
                spacing: 8 * u

                // name · link · mode · armed
                Item {
                    width: parent.width; height: 24 * u
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8 * u
                        Text { anchors.verticalCenter: parent.verticalCenter; text: MLTheme.uavName(card.v ? card.v.id : 0); color: card.col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                        MLText { anchors.verticalCenter: parent.verticalCenter; text: card.v ? MLTheme.vehicleTypeName(card.v) : ""; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
                    }
                    Row {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        spacing: 6 * u
                        MLChip { text: card.lost ? qsTr("두절") : "LINK"; tone: card.lost ? MLTheme.warning : MLTheme.active; blink: card.lost }
                        MLChip { text: card.v && card.v.armed ? qsTr("시동") : qsTr("대기"); tone: card.v && card.v.armed ? MLTheme.caution : MLTheme.dim }
                        MLIconButton { glyph: "◎"; size: 24 * u; tip: qsTr("지도 중심으로"); onClicked: if (card.v && card.v.coordinate.isValid) MLState.centerRequested(card.v.coordinate) }
                    }
                }
                // numbers
                Row {
                    width: parent.width
                    spacing: 0
                    Repeater {
                        model: [
                            { k: "ALT", v: isNaN(card.alt) ? "—" : card.alt.toFixed(1), u: "m", c: MLTheme.text },
                            { k: "GS",  v: isNaN(card.gs) ? "—" : card.gs.toFixed(1), u: "m/s", c: MLTheme.text },
                            { k: "HDG", v: isNaN(card.hdg) ? "—" : ("00" + Math.round(card.hdg)).slice(-3), u: "°", c: MLTheme.text },
                            { k: "BATT", v: isNaN(card.pct) ? "—" : card.pct.toFixed(0), u: "%", c: isNaN(card.pct) ? MLTheme.text : (card.pct < 15 ? MLTheme.warning : (card.pct < 30 ? MLTheme.caution : MLTheme.text)) },
                            { k: "GNSS", v: isNaN(card.lock) ? "—" : (card.lock >= 6 ? "RTK" : (card.lock === 5 ? "FLT" : (card.lock >= 3 ? "3D" : "NO"))), u: isNaN(card.sats) ? "" : String(card.sats), c: !isNaN(card.lock) && card.lock < 3 ? MLTheme.warning : MLTheme.text }
                        ]
                        Column {
                            width: inner.width / 5
                            Text { text: modelData.k; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.6 * u }
                            Row {
                                spacing: 3 * u
                                Text { text: modelData.v; color: modelData.c; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue; font.weight: Font.Medium }
                                Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 2 * u; text: modelData.u; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                            }
                        }
                    }
                }
                // mode · mission progress
                Item {
                    width: parent.width; height: 20 * u
                    MLText { id: modeT; anchors.verticalCenter: parent.verticalCenter; text: card.v ? card.v.flightMode : ""; color: MLTheme.text; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; width: Math.min(implicitWidth, parent.width * 0.4) }
                    Rectangle {
                        id: track
                        anchors.left: modeT.right; anchors.leftMargin: 10 * u
                        anchors.right: wpT.left; anchors.rightMargin: 10 * u
                        anchors.verticalCenter: parent.verticalCenter
                        height: 4 * u; radius: 2 * u; color: MLTheme.line
                        Rectangle { height: parent.height; radius: parent.radius; color: card.col; width: card.total > 0 && card.cur > 0 ? parent.width * Math.min(1, card.cur / card.total) : 0; Behavior on width { NumberAnimation { duration: MLTheme.animSlow } } }
                    }
                    Text { id: wpT; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: card.total > 0 ? "WP " + Math.max(0, card.cur) + "/" + card.total : qsTr("미션 없음"); color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                }
                // ACACT
                Rectangle {
                    visible: !!card.gd
                    width: parent.width
                    height: acCol.implicitHeight + 12 * u
                    radius: 6 * u
                    color: card.phase === "avoid" ? MLTheme.warningFill : (card.phase === "return" ? MLTheme.cautionFill : "transparent")
                    border.color: MLTheme.alpha(root.phaseColor(card.phase), 0.45)
                    Column {
                        id: acCol
                        x: 10 * u; y: 6 * u; width: parent.width - 20 * u
                        spacing: 3 * u
                        Row {
                            spacing: 8 * u
                            Text { text: "ACACT"; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
                            MLText { text: root.phaseText(card.phase); color: root.phaseColor(card.phase); font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                            Text { visible: card.gd && card.gd.takeovers > 0; text: qsTr("개입 %1회").arg(card.gd ? card.gd.takeovers : 0); color: MLTheme.label; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MLText {
                            visible: card.gd && card.gd.reason !== undefined && card.gd.reason !== ""
                            width: parent.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                            text: card.gd ? card.gd.reason : ""
                            color: MLTheme.text; font.pixelSize: MLTheme.fsLabel
                        }
                    }
                }
            }
        }
    }
}
