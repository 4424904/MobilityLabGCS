import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Right column of the console: mission on the vehicle at a glance.
//
//   ┌ 미션 MISSION ───────────────── 진행 중 ┐
//   │ [진행 3/7] [다음 WP 412 m]             │
//   │ [총 거리 2.4 km] [예상 시간 6:20]       │
//   │ ▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬▬                  │
//   │ #  명령        고도      구간           │
//   │ 1  이륙        80 m      —              │
//   │ ▶2 경유점      80 m      412 m          │
//   │ ...                                    │
//   │ [ 미션 계획 화면 ]                      │
//   └────────────────────────────────────────┘
//
// Read-only: editing and uploading stay in QGC's Plan view (button).
MLPanel {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property var  _pmc:        globals.planMasterControllerFlyView
    readonly property var  _mc:         _pmc ? _pmc.missionController : null
    readonly property var  _items:      _mc ? _mc.visualItems : null
    readonly property int  _count:      _items ? Math.max(0, _items.count - 1) : 0      // item 0 is the home/settings item
    readonly property int  _cur:        _mc ? _mc.currentMissionIndex : -1
    readonly property string _mode:     vehicle ? String(vehicle.flightMode) : ""
    readonly property bool _running:    !!vehicle && vehicle.flying && /mission|auto/i.test(_mode) && !/rtl|return|land|loiter|hold/i.test(_mode)
    readonly property real _fw:         ScreenTools.defaultFontPixelWidth
    readonly property real _fh:         ScreenTools.defaultFontPixelHeight

    function _v(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined) ? NaN : v
    }
    function _dist(m) {
        if (isNaN(m) || m <= 0) return "—"
        return m >= 1000 ? (m / 1000).toFixed(2) + " km" : m.toFixed(0) + " m"
    }
    function _time(s) {
        if (isNaN(s) || s <= 0) return "—"
        var h = Math.floor(s / 3600), mnt = Math.floor((s % 3600) / 60), sec = Math.floor(s % 60)
        return (h > 0 ? h + ":" + ("0" + mnt).slice(-2) : mnt) + ":" + ("0" + sec).slice(-2)
    }
    function _commandName(item) {
        if (!item) return ""
        var n = String(item.commandName)
        var l = n.toLowerCase()
        if (item.isTakeoffItem || l.indexOf("takeoff") >= 0)   return qsTr("이륙")
        if (item.isLandCommand || l === "land")                return qsTr("착륙")
        if (l.indexOf("return") >= 0 || l === "rtl")           return qsTr("복귀")
        if (l === "waypoint")                                  return qsTr("경유점")
        if (l.indexOf("loiter") >= 0)                          return qsTr("선회 대기")
        if (l.indexOf("survey") >= 0)                          return qsTr("측량 패턴")
        if (l.indexOf("roi") >= 0 || l.indexOf("region") >= 0) return qsTr("관심 지점")
        if (l.indexOf("speed") >= 0)                           return qsTr("속도 변경")
        if (l.indexOf("delay") >= 0)                           return qsTr("대기")
        if (l.indexOf("vtol") >= 0)                            return n
        return n
    }

    title:          qsTr("미션")
    tag:            "MISSION"
    detail:         !vehicle ? "" : (_count === 0 ? qsTr("미션 없음") : (_running ? qsTr("진행 중") : qsTr("대기")))
    detailColor:    _running ? MLTheme.ok : MLTheme.dim

    // ---- Summary ----------------------------------------------------------
    Column {
        id:         summary
        width:      parent.width
        spacing:    root._fh * 0.5

        Grid {
            id:         summaryGrid
            width:      parent.width
            columns:    2
            spacing:    root._fw * 0.6

            readonly property real _w: (width - spacing) / 2

            MLStatTile {
                width:  summaryGrid._w
                label:  qsTr("진행")
                value:  root._count === 0 ? "—" : (root._cur > 0 ? root._cur : 0) + " / " + root._count
                level:  root._count === 0 ? 0 : 1
            }
            MLStatTile {
                width:  summaryGrid._w
                label:  qsTr("다음 WP 거리")
                readonly property real _d: root.vehicle && root._running ? root._v(root.vehicle.distanceToNextWP) : NaN
                value:  root._dist(_d)
                level:  isNaN(_d) ? 0 : 1
            }
            MLStatTile {
                width:  summaryGrid._w
                label:  qsTr("총 거리")
                value:  root._mc && root._count > 0 ? root._dist(root._mc.missionTotalDistance) : "—"
                level:  root._count === 0 ? 0 : 1
            }
            MLStatTile {
                width:  summaryGrid._w
                label:  qsTr("예상 비행 시간")
                value:  root._mc && root._count > 0 ? root._time(root._mc.missionTime) : "—"
                level:  root._count === 0 ? 0 : 1
            }
        }

        // Progress through the mission items
        Rectangle {
            width:      parent.width
            height:     Math.max(4, root._fh * 0.3)
            radius:     height / 2
            color:      MLTheme.panelRaised
            visible:    root._count > 0

            Rectangle {
                width:      parent.width * Math.max(0, Math.min(1, root._cur / Math.max(1, root._count)))
                height:     parent.height
                radius:     parent.radius
                color:      root._running ? MLTheme.ok : MLTheme.accent
                Behavior on width { NumberAnimation { duration: 300 } }
            }
        }
    }

    // ---- Item list --------------------------------------------------------
    Item {
        id:                 listHeader
        anchors.top:        summary.bottom
        anchors.topMargin:  root._fh * 0.6
        width:              parent.width
        height:             root._fh * 1.4
        visible:            root._count > 0

        readonly property real _c0: root._fw * 4
        readonly property real _c2: width * 0.26
        readonly property real _c3: width * 0.26

        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
        QGCLabel { x: root._fw * 0.6; anchors.verticalCenter: parent.verticalCenter; text: "#"; color: MLTheme.faint; font.pointSize: ScreenTools.smallFontPointSize }
        QGCLabel { x: listHeader._c0; anchors.verticalCenter: parent.verticalCenter; text: qsTr("명령"); color: MLTheme.faint; font.pointSize: ScreenTools.smallFontPointSize }
        QGCLabel { x: parent.width - listHeader._c3 - listHeader._c2; width: listHeader._c2; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: qsTr("고도"); color: MLTheme.faint; font.pointSize: ScreenTools.smallFontPointSize }
        QGCLabel { x: parent.width - listHeader._c3; width: listHeader._c3 - root._fw * 0.6; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter; text: qsTr("구간 거리"); color: MLTheme.faint; font.pointSize: ScreenTools.smallFontPointSize }
    }

    ListView {
        id:                 itemList
        anchors.top:        listHeader.bottom
        anchors.topMargin:  root._fh * 0.2
        anchors.bottom:     planButton.top
        anchors.bottomMargin: root._fh * 0.5
        width:              parent.width
        visible:            root._count > 0
        clip:               true
        model:              root._items
        boundsBehavior:     Flickable.StopAtBounds
        spacing:            1

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Keep the current item in view while the mission runs
        Connections {
            target: root._mc
            function onCurrentMissionIndexChanged() {
                if (root._cur > 0) itemList.positionViewAtIndex(root._cur, ListView.Contain)
            }
        }

        delegate: Rectangle {
            id:         row
            required property var object
            required property int index

            readonly property bool _current: !!object && object.isCurrentItem && index > 0
            readonly property bool _done:    root._cur > 0 && index > 0 && index < root._cur

            visible:    index > 0
            width:      ListView.view.width
            height:     index > 0 ? root._fh * 1.75 : 0
            radius:     root._fw * 0.3
            color:      _current ? "#1d4a3a" : (index % 2 === 0 ? MLTheme.tile : "transparent")
            border.width: _current ? 1 : 0
            border.color: MLTheme.ok

            QGCLabel {
                x:                      root._fw * 0.6
                anchors.verticalCenter: parent.verticalCenter
                text:                   row._current ? "▶" : (row.object ? row.object.sequenceNumber : "")
                color:                  row._current ? MLTheme.ok : (row._done ? MLTheme.faint : MLTheme.dim)
                font.family:            ScreenTools.fixedFontFamily
                font.pointSize:         ScreenTools.smallFontPointSize
                font.bold:              row._current
            }
            QGCLabel {
                x:                      listHeader._c0
                width:                  parent.width - listHeader._c0 - listHeader._c2 - listHeader._c3
                anchors.verticalCenter: parent.verticalCenter
                text:                   root._commandName(row.object)
                color:                  row._current ? MLTheme.text : (row._done ? MLTheme.faint : MLTheme.label)
                elide:                  Text.ElideRight
                font.bold:              row._current
            }
            QGCLabel {
                x:                      parent.width - listHeader._c3 - listHeader._c2
                width:                  listHeader._c2
                horizontalAlignment:    Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var o = row.object
                    if (!o || !o.isSimpleItem || !o.altitude || !o.specifiesCoordinate) return "—"
                    return o.altitude.valueString + " " + o.altitude.units
                }
                color:                  row._done ? MLTheme.faint : MLTheme.text
                font.family:            ScreenTools.fixedFontFamily
                font.pointSize:         ScreenTools.smallFontPointSize
            }
            QGCLabel {
                x:                      parent.width - listHeader._c3
                width:                  listHeader._c3 - root._fw * 0.6
                horizontalAlignment:    Text.AlignRight
                anchors.verticalCenter: parent.verticalCenter
                text:                   row.object && row.object.specifiesCoordinate ? root._dist(row.object.distance) : "—"
                color:                  row._done ? MLTheme.faint : MLTheme.text
                font.family:            ScreenTools.fixedFontFamily
                font.pointSize:         ScreenTools.smallFontPointSize
            }
        }
    }

    // ---- No mission -------------------------------------------------------
    Column {
        anchors.top:                summary.bottom
        anchors.bottom:             planButton.top
        anchors.horizontalCenter:   parent.horizontalCenter
        visible:                    root._count === 0
        spacing:                    root._fh * 0.3
        topPadding:                 Math.max(0, (height - implicitHeight) / 2)

        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           root.vehicle ? qsTr("기체에 미션이 없습니다") : qsTr("기체 연결 대기")
            color:          MLTheme.label
        }
        QGCLabel {
            anchors.horizontalCenter: parent.horizontalCenter
            visible:        !!root.vehicle
            text:           qsTr("아래 버튼으로 미션을 만들고 업로드하세요")
            color:          MLTheme.faint
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    // ---- Plan view --------------------------------------------------------
    Rectangle {
        id:             planButton
        anchors.bottom: parent.bottom
        width:          parent.width
        height:         root._fh * 2.3
        radius:         root._fw * 0.5
        color:          planMouse.pressed ? "#173640" : (planMouse.containsMouse ? "#1b2c36" : MLTheme.panelRaised)
        border.width:   1
        border.color:   planMouse.containsMouse ? MLTheme.accent : MLTheme.lineStrong

        QGCLabel {
            anchors.centerIn:   parent
            text:               root._count > 0 ? qsTr("미션 편집 · 업로드  (계획 화면)") : qsTr("미션 만들기  (계획 화면)")
            color:              MLTheme.text
            font.bold:          true
        }
        MouseArea {
            id:             planMouse
            anchors.fill:   parent
            hoverEnabled:   true
            cursorShape:    Qt.PointingHandCursor
            onClicked:      if (typeof mainWindow !== "undefined") mainWindow.showPlanView()
        }
    }
}
