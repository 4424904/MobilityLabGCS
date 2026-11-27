import QtQuick
import QtQuick.Controls
import QtLocation
import QtPositioning

import QGroundControl

// Plan view additions (QGC's mission editor stays as it is):
//   panel  the plan being edited (vehicle colour, distance, time, height, items) and the
//          multi-vehicle ACACT mission check — every vehicle's mission with its length, time and
//          problems, pairs whose planned tracks come close, and "ACACT 재검증" after editing.
//          Errors block the fleet start in the ACACT console; warnings are shown, not blocking.
//   map    the missions of the other vehicles in their identity colours, with direction arrows,
//          and the places where two planned tracks come within the safe separation.
Item {
    id: root
    property var planMasterController
    property var map
    readonly property real u:   MLTheme.u
    readonly property var  _mc: planMasterController ? planMasterController.missionController : null
    readonly property bool _g:  typeof mlGuard !== "undefined"
    readonly property var  _chk: _g ? mlGuard.missionCheck : ({})
    readonly property var  _veh: _chk && _chk.vehicles ? _chk.vehicles : []
    readonly property var  _pairs: _chk && _chk.pairs ? _chk.pairs : []
    readonly property var  _active: QGroundControl.multiVehicleManager.activeVehicle
    property bool expanded: true

    function sevColor(l) { return l >= 2 ? MLTheme.warning : (l === 1 ? MLTheme.caution : MLTheme.active) }

    // ---- other vehicles' missions on the map ---------------------------------------------------
    Instantiator {
        model: root._veh.length
        delegate: QtObject {
            readonly property var vd: index < root._veh.length ? root._veh[index] : null
            readonly property bool show: !!vd && !!vd.path && vd.path.length > 1 && (!root._active || vd.sysid !== root._active.id)
            property var line: MapPolyline {
                visible: show
                line.width: 3
                line.color: String(MLTheme.alpha(MLTheme.vehicleColor(vd ? vd.sysid : 1), 0.85))
                path: {
                    var p = []
                    if (vd && vd.path) for (var i = 0; i < vd.path.length; i++) p.push(QtPositioning.coordinate(vd.path[i].lat, vd.path[i].lon))
                    return p
                }
            }
            property var tag: MapQuickItem {
                visible: show
                coordinate: show ? QtPositioning.coordinate(vd.path[0].lat, vd.path[0].lon) : QtPositioning.coordinate()
                anchorPoint.x: tagBox.width / 2
                anchorPoint.y: tagBox.height + 6 * root.u
                sourceItem: Rectangle {
                    id: tagBox
                    width: tagText.implicitWidth + 12 * root.u; height: 22 * root.u; radius: 4 * root.u
                    color: MLTheme.vehicleColor(vd ? vd.sysid : 1)
                    Text { id: tagText; anchors.centerIn: parent; text: vd ? vd.id + qsTr(" 미션") : ""; color: "white"; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.weight: Font.DemiBold }
                }
            }
        }
        onObjectAdded: (i, o) => { if (root.map) { root.map.addMapItem(o.line); root.map.addMapItem(o.tag) } }
        onObjectRemoved: (i, o) => { if (root.map) { root.map.removeMapItem(o.line); root.map.removeMapItem(o.tag) } }
    }
    Instantiator {
        model: root._pairs.length
        delegate: QtObject {
            readonly property var p: index < root._pairs.length ? root._pairs[index] : null
            readonly property bool show: !!p && p.worst >= 1 && p.lat !== undefined && p.lat !== null
            property var ring: MapCircle {
                visible: show
                center: show ? QtPositioning.coordinate(p.lat, p.lon) : QtPositioning.coordinate()
                radius: typeof mlGuard !== "undefined" && mlGuard.config.d_safe ? mlGuard.config.d_safe : 10
                color: String(MLTheme.alpha(root.sevColor(p ? p.worst : 0), 0.18))
                border.color: root.sevColor(p ? p.worst : 0)
                border.width: 2
            }
        }
        onObjectAdded: (i, o) => { if (root.map) root.map.addMapItem(o.ring) }
        onObjectRemoved: (i, o) => { if (root.map) root.map.removeMapItem(o.ring) }
    }

    // ---- panel ------------------------------------------------------------------------------------
    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 70 * u
        anchors.bottomMargin: 70 * u
        width: 380 * u
        height: root.expanded ? Math.min(col.implicitHeight + 24 * u, root.height - 160 * u) : 46 * u
        radius: MLTheme.panelRadius
        color: MLTheme.glassStrong
        border.color: MLTheme.glassEdge
        clip: true
        Behavior on height { NumberAnimation { duration: MLTheme.anim; easing.type: Easing.OutCubic } }

        Flickable {
            anchors.fill: parent
            contentHeight: col.implicitHeight + 24 * root.u
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: col
                x: 14 * root.u; y: 12 * root.u
                width: panel.width - 28 * root.u
                spacing: 8 * root.u

                Item {
                    width: parent.width; height: 24 * root.u
                    Row {
                        spacing: 8 * root.u; anchors.verticalCenter: parent.verticalCenter
                        Rectangle { width: 10 * root.u; height: 10 * root.u; radius: 5 * root.u; color: root._active ? MLTheme.vehicleColor(root._active.id) : MLTheme.dim; anchors.verticalCenter: parent.verticalCenter }
                        MLText { text: root._active ? qsTr("%1 미션 계획").arg(MLTheme.uavName(root._active.id)) : qsTr("미션 계획 (기체 없음)"); font.pixelSize: MLTheme.fsBody; font.weight: Font.DemiBold }
                    }
                    MLIconButton { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: root.expanded ? "−" : "+"; size: 24 * root.u; onClicked: root.expanded = !root.expanded }
                }
                // stats of the plan being edited (QGC's own computation)
                Row {
                    width: parent.width
                    Repeater {
                        model: [
                            { k: qsTr("비행 거리"), v: root._mc ? MLTheme.distance(root._mc.missionTotalDistance).v + " " + MLTheme.distance(root._mc.missionTotalDistance).u : "—" },
                            { k: qsTr("예상 시간"), v: root._mc ? MLTheme.duration(root._mc.missionTime) : "—" },
                            { k: qsTr("최대 거리"), v: root._mc ? MLTheme.distance(root._mc.missionMaxTelemetry).v + " " + MLTheme.distance(root._mc.missionMaxTelemetry).u : "—" },
                            { k: qsTr("항목"), v: root._mc ? Math.max(0, root._mc.visualItems.count - 1) : "—" }
                        ]
                        Column {
                            width: col.width / 4
                            Text { text: modelData.k; color: MLTheme.dim; font.family: MLTheme.sans; font.pixelSize: MLTheme.fsLabel }
                            Text { text: modelData.v; color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsValue }
                        }
                    }
                }

                MLSectionTitle { text: qsTr("다기체 미션 검사 (ACACT)"); detail: root._chk.time ? qsTr("검사 %1").arg(root._chk.time) : "" }
                Row {
                    spacing: 8 * root.u
                    MLChip {
                        text: !root._g ? "—" : (root._chk.errors > 0 ? qsTr("오류 %1 · 시작 차단").arg(root._chk.errors) : (root._chk.warnings > 0 ? qsTr("주의 %1").arg(root._chk.warnings) : qsTr("이상 없음")))
                        tone: root._chk.errors > 0 ? MLTheme.warning : (root._chk.warnings > 0 ? MLTheme.caution : MLTheme.active)
                        filled: root._chk.errors > 0
                        height: 26 * root.u
                    }
                    MLIconButton { label: qsTr("ACACT 재검증"); glyph: "↻"; size: 26 * root.u; enabledState: root._g; onClicked: mlGuard.validateMissions() }
                }
                Repeater {
                    model: root._veh.length
                    Rectangle {
                        readonly property var vd: root._veh[index]
                        width: col.width
                        height: vc.implicitHeight + 12 * root.u
                        radius: 6 * root.u
                        color: MLTheme.tile
                        border.color: MLTheme.alpha(root.sevColor(vd.worst), vd.worst > 0 ? 0.7 : 0.25)
                        Rectangle { width: 4 * root.u; height: parent.height - 10 * root.u; y: 5 * root.u; radius: 2 * root.u; color: MLTheme.vehicleColor(vd.sysid) }
                        Column {
                            id: vc
                            x: 12 * root.u; y: 6 * root.u; width: parent.width - 20 * root.u
                            spacing: 2 * root.u
                            Row {
                                spacing: 8 * root.u
                                Text { text: vd.id; color: MLTheme.vehicleColor(vd.sysid); font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold }
                                Text { text: vd.navItems > 0 ? qsTr("%1 km · %2 · 최고 %3 m · 경유점 %4").arg((vd.length / 1000).toFixed(2)).arg(MLTheme.duration(vd.duration)).arg(Number(vd.maxAlt).toFixed(0)).arg(vd.navItems) : qsTr("미션 없음"); color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel }
                            }
                            Repeater {
                                model: vd.issues ? vd.issues.length : 0
                                MLText {
                                    readonly property var is: vd.issues[index]
                                    width: vc.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                                    text: (is.level >= 2 ? "✕ " : "! ") + (is.seq !== undefined && is.seq >= 0 ? "#" + (is.seq + 1) + " " : "") + is.text
                                    color: root.sevColor(is.level); font.pixelSize: MLTheme.fsLabel
                                }
                            }
                        }
                    }
                }
                Repeater {
                    model: root._pairs.length
                    MLText {
                        readonly property var p: root._pairs[index]
                        visible: p.worst >= 1
                        width: col.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                        text: qsTr("%1·%2 계획 경로 최소 %3 m%4").arg(p.a).arg(p.b).arg(p.pathMin !== undefined && p.pathMin !== null ? Number(p.pathMin).toFixed(1) : "—")
                              .arg(p.timedMin !== undefined && p.timedMin !== null ? qsTr(" · 동시 출발 시 %1 m (%2초)").arg(Number(p.timedMin).toFixed(1)).arg(Number(p.timedAt).toFixed(0)) : "")
                        color: root.sevColor(p.worst); font.pixelSize: MLTheme.fsLabel
                    }
                }
                MLText {
                    visible: root._veh.length === 0
                    width: col.width; wrapMode: Text.WordWrap; elide: Text.ElideNone
                    color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel
                    text: qsTr("기체가 연결되면 각 기체에 올라간 미션을 함께 검사합니다. 미션을 업로드한 뒤 [ACACT 재검증]을 누르세요.")
                }
            }
        }
    }
}
