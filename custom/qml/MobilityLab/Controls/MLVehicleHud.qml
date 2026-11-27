import QtQuick

import QGroundControl

// Selected-vehicle HUD over the map (shown when the instrument panel is folded away, or always
// when chosen in 화면 구성): identity, mode, link, and the primary numbers in large type.
Rectangle {
    id: root
    readonly property real u: MLTheme.u
    readonly property var  v: QGroundControl.multiVehicleManager.activeVehicle
    function fv(f) { if (!f) return NaN; var x = f.rawValue; return (x === undefined || x === null) ? NaN : Number(x) }
    readonly property real alt: v ? fv(v.altitudeRelative) : NaN
    readonly property real gs:  v ? fv(v.groundSpeed) : NaN
    readonly property real vs:  v ? fv(v.climbRate) : NaN
    readonly property real hdg: v ? fv(v.heading) : NaN
    readonly property real dh:  v ? fv(v.distanceToHome) : NaN
    readonly property var  bat: v && v.batteries.count > 0 ? v.batteries.get(0) : null
    readonly property real pct: bat ? fv(bat.percentRemaining) : NaN
    readonly property bool lost: !!v && v.vehicleLinkManager.communicationLost
    readonly property color col: v ? MLTheme.vehicleColor(v.id) : MLTheme.dim

    visible: !!v
    width: row.implicitWidth + 36 * u
    height: 76 * u
    radius: MLTheme.panelRadius
    color: MLTheme.glassStrong
    border.color: lost ? MLTheme.warning : MLTheme.glassEdge
    border.width: lost ? 2 : 1

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 26 * root.u
        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.u
            Row {
                spacing: 8 * root.u
                Rectangle { width: 4 * root.u; height: 18 * root.u; radius: 2 * root.u; color: root.col; anchors.verticalCenter: parent.verticalCenter }
                Text { text: root.v ? MLTheme.uavName(root.v.id) : ""; color: root.col; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
            }
            Row {
                spacing: 6 * root.u
                MLChip { text: root.v ? root.v.flightMode : ""; tone: MLTheme.accent }
                MLChip { text: root.lost ? qsTr("두절") : (root.v && root.v.armed ? qsTr("시동") : qsTr("대기")); tone: root.lost ? MLTheme.warning : (root.v && root.v.armed ? MLTheme.caution : MLTheme.dim); blink: root.lost }
            }
        }
        Rectangle { width: 1; height: 48 * root.u; color: MLTheme.line; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
            model: [
                { k: "ALT", v: isNaN(root.alt) ? "—" : root.alt.toFixed(1), u: "m", c: MLTheme.bright },
                { k: "GS", v: isNaN(root.gs) ? "—" : root.gs.toFixed(1), u: "m/s", c: MLTheme.bright },
                { k: "V/S", v: isNaN(root.vs) ? "—" : (root.vs >= 0 ? "+" : "") + root.vs.toFixed(1), u: "m/s", c: MLTheme.text },
                { k: "HDG", v: isNaN(root.hdg) ? "—" : ("00" + Math.round(root.hdg)).slice(-3), u: "°", c: MLTheme.text },
                { k: "HOME", v: isNaN(root.dh) ? "—" : MLTheme.distance(root.dh).v, u: isNaN(root.dh) ? "" : MLTheme.distance(root.dh).u, c: MLTheme.text },
                { k: "BATT", v: isNaN(root.pct) ? "—" : root.pct.toFixed(0), u: "%", c: isNaN(root.pct) ? MLTheme.text : (root.pct < 15 ? MLTheme.warning : (root.pct < 30 ? MLTheme.caution : MLTheme.text)) }
            ]
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: modelData.k; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 1 * root.u }
                Row {
                    spacing: 3 * root.u
                    Text { text: modelData.v; color: modelData.c; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBig; font.weight: Font.Medium }
                    Text { anchors.bottom: parent.bottom; anchors.bottomMargin: 4 * root.u; text: modelData.u; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
                }
            }
        }
    }
}
