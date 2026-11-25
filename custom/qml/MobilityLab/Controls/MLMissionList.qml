import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 미션: the selected vehicle's mission (read-only), progress, current item
// highlighted. Editing / uploading opens QGC's Plan view.
Column {
    id: root

    property var  vehicle: QGroundControl.multiVehicleManager.activeVehicle
    property real maxListHeight: 8 * 28 * MLTheme.u

    readonly property real u:       MLTheme.u
    readonly property var  _mc:     globals.planMasterControllerFlyView ? globals.planMasterControllerFlyView.missionController : null
    readonly property var  _items:  _mc ? _mc.visualItems : null
    readonly property int  _count:  _items ? Math.max(0, _items.count - 1) : 0
    readonly property int  _cur:    _mc ? _mc.currentMissionIndex : -1

    function _dist(m) { var d = MLTheme.distance(m); return d.v === "—" ? "—" : d.v + " " + d.u }
    function _name(item) {
        if (!item) return ""
        var n = String(item.commandName), l = n.toLowerCase()
        if (item.isTakeoffItem || l.indexOf("takeoff") >= 0)   return qsTr("이륙")
        if (item.isLandCommand || l === "land")                return qsTr("착륙")
        if (l.indexOf("return") >= 0 || l === "rtl")           return qsTr("이륙 위치로 복귀")
        if (l === "waypoint")                                  return qsTr("경유점")
        if (l.indexOf("loiter") >= 0)                          return qsTr("선회 대기")
        if (l.indexOf("survey") >= 0)                          return qsTr("측량 패턴")
        if (l.indexOf("roi") >= 0 || l.indexOf("region") >= 0) return qsTr("관심 지점")
        if (l.indexOf("speed") >= 0)                           return qsTr("속도 변경")
        return n
    }

    MLSection {
        width:  root.width
        title:  root.vehicle && QGroundControl.multiVehicleManager.vehicles.count > 1 ? qsTr("미션 · UAV %1").arg(("0" + root.vehicle.id).slice(-2)) : qsTr("미션")
        detail: root._count === 0 ? "" : (Math.max(0, root._cur) + " / " + root._count + " · " + root._dist(root._mc.missionTotalDistance) + " · " + MLTheme.duration(root._mc.missionTime))
    }

    Item {
        visible:    root._count > 0
        width:      root.width
        height:     11 * u
        Rectangle { x: 20 * u; width: parent.width - 40 * u; height: 3 * u; color: "#1E242B"
            Rectangle { height: parent.height; width: parent.width * Math.max(0, Math.min(1, root._cur / Math.max(1, root._count))); color: MLTheme.accent
                Behavior on width { NumberAnimation { duration: 300 } } } }
    }

    ListView {
        id:             list
        visible:        root._count > 0
        x:              12 * u
        width:          root.width - 24 * u
        height:         Math.min(contentHeight, root.maxListHeight)
        clip:           true
        model:          root._items
        boundsBehavior: Flickable.StopAtBounds
        interactive:    contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: list.interactive ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }

        Connections {
            target: root._mc
            function onCurrentMissionIndexChanged() { if (root._cur > 0) list.positionViewAtIndex(root._cur, ListView.Contain) }
        }

        delegate: Rectangle {
            id: row
            required property var object
            required property int index
            readonly property bool _current: !!object && object.isCurrentItem && index > 0
            readonly property bool _done:    root._cur > 0 && index > 0 && index < root._cur
            readonly property color _fg:     _done ? MLTheme.faint : (_current ? MLTheme.bright : MLTheme.label)

            visible:    index > 0
            width:      ListView.view.width
            height:     index > 0 ? 28 * u : 0
            color:      _current ? "#122029" : "transparent"

            Text { x: 8 * u; anchors.verticalCenter: parent.verticalCenter; text: row.object ? ("0" + row.object.sequenceNumber).slice(-2) : ""; color: row._current ? MLTheme.accent : row._fg; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
            MLText { x: 44 * u; width: parent.width - 44 * u - 136 * u; anchors.verticalCenter: parent.verticalCenter; text: root._name(row.object); color: row._fg; font.pixelSize: MLTheme.fsSmall }
            Text {
                x: parent.width - 136 * u; width: 56 * u; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                text: { var o = row.object; if (!o || !o.isSimpleItem || !o.altitude || !o.specifiesCoordinate) return "—"; var a = Number(o.altitude.rawValue); return isNaN(a) ? "—" : a.toFixed(0) + " m" }
                color: row._fg; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
            }
            Text {
                x: parent.width - 72 * u; width: 64 * u; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter
                text: row.object && row.object.specifiesCoordinate ? root._dist(row.object.distance) : "—"
                color: row._fg; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall
            }
        }
    }

    Item {
        visible:    root._count === 0
        width:      root.width
        height:     34 * u
        MLText { x: 20 * u; anchors.verticalCenter: parent.verticalCenter; text: root.vehicle ? qsTr("기체에 올라간 미션이 없습니다") : qsTr("기체 연결 대기"); color: MLTheme.faint }
    }

    Item {
        width:  root.width
        height: 64 * u
        component LinkButton: Rectangle {
            id: lb
            property string label
            signal fire()
            height: 40 * MLTheme.u
            radius: MLTheme.radius
            color:  lbMouse.pressed ? "#16222B" : (lbMouse.containsMouse ? "#11171D" : "transparent")
            border.width: 1
            border.color: lbMouse.containsMouse ? MLTheme.accent : MLTheme.lineStrong
            MLText { anchors.centerIn: parent; text: lb.label; color: "#9FD8F2"; font.pixelSize: MLTheme.fsSmall; font.letterSpacing: 0.5 * MLTheme.u }
            MouseArea { id: lbMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lb.fire() }
        }
        LinkButton {
            x: 20 * u; y: 10 * u
            width: parent.width - 40 * u - reload.width - 8 * u
            label: root._count > 0 ? qsTr("미션 편집 · 업로드") : qsTr("미션 만들기")
            onFire: if (typeof mainWindow !== "undefined") mainWindow.showPlanView()
        }
        LinkButton {
            id: reload
            anchors.right: parent.right; anchors.rightMargin: 20 * u; y: 10 * u
            width: 96 * u
            visible: !!root.vehicle && typeof mlTools !== "undefined"
            label: qsTr("다시 읽기")
            onFire: mlTools.reloadMission(root.vehicle)
        }
    }
}
