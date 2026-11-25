import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 기체 목록 (shown when more than one vehicle is connected). Replaces QGC's
// map-corner multi-vehicle panel.
//
//   ┌ 기체 FLEET ─────────────────────────────── 2대 ┐
//   │ ┃ 1  헬리콥터 #1        [시동 ON] [✓]  [미션] │  ← 선택된 기체 (콘솔이 이 기체를 표시)
//   │ ┃    자동 · 82 m · 14 m/s · 72%              │
//   │   2  멀티콥터 #2        [시동 ON] [ ]  [미션] │
//   │ ─────────────────────────────────────────── │
//   │ 체크한 기체 1대: [시동][시동 끄기][미션 시작][일시정지] │
//   └──────────────────────────────────────────────┘
//
// Click a card to make that vehicle the one the console shows and commands.
// [미션] selects the vehicle and opens the Plan view, so each vehicle gets its
// own mission. The check boxes pick vehicles for the group commands below
// (each needs two presses, like the main command bar).
MLPanel {
    id: root

    readonly property var  _mvm:        QGroundControl.multiVehicleManager
    readonly property var  _vehicles:   _mvm.vehicles
    readonly property var  _selected:   _mvm.selectedVehicles
    readonly property var  _active:     _mvm.activeVehicle
    readonly property real _fw:         ScreenTools.defaultFontPixelWidth
    readonly property real _fh:         ScreenTools.defaultFontPixelHeight
    readonly property var  _colors:     [ "#4fd3ea", "#ef5fe0", "#f5b331", "#7cdc5a", "#ff8a65", "#9fa8ff" ]

    function _v(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined) ? NaN : v
    }
    function isSelected(vehicleId) {
        for (var i = 0; i < _selected.count; i++) {
            if (_selected.get(i).id === vehicleId) return true
        }
        return false
    }
    function forSelected(fn) {
        for (var i = 0; i < _selected.count; i++) {
            var v = _selected.get(i)
            if (v && !v.vehicleLinkManager.communicationLost) fn(v)
        }
    }
    function anySelected(test) {
        for (var i = 0; i < _selected.count; i++) {
            var v = _selected.get(i)
            if (v && test(v)) return true
        }
        return false
    }

    title:      qsTr("기체")
    tag:        "FLEET"
    detail:     qsTr("%1대 연결").arg(_vehicles.count)

    implicitHeight: _fh * 1.9 + padding * 1.8 + list.contentHeight + actions.height + _fh * 0.6

    ListView {
        id:             list
        anchors.top:    parent.top
        anchors.bottom: actions.top
        anchors.bottomMargin: root._fh * 0.4
        width:          parent.width
        clip:           true
        spacing:        root._fh * 0.3
        model:          root._vehicles
        boundsBehavior: Flickable.StopAtBounds

        delegate: Rectangle {
            id:     card
            required property var object
            required property int index

            readonly property var   _veh:       object
            readonly property bool  _isActive:  _veh === root._active
            readonly property bool  _lost:      _veh && _veh.vehicleLinkManager.communicationLost
            readonly property color _tagColor:  root._colors[index % root._colors.length]
            readonly property real  _bat: {
                if (!_veh || !_veh.batteries || _veh.batteries.count === 0) return NaN
                var b = _veh.batteries.get(0)
                return b ? root._v(b.percentRemaining) : NaN
            }

            width:          ListView.view.width
            height:         root._fh * 3.3
            radius:         root._fw * 0.4
            color:          _isActive ? "#14303a" : (cardMouse.containsMouse ? "#16222b" : MLTheme.tile)
            border.width:   _isActive ? 1.5 : 1
            border.color:   _lost ? MLTheme.warning : (_isActive ? MLTheme.accent : MLTheme.line)

            // colour tag + number
            Rectangle {
                id:                     tag
                anchors.left:           parent.left
                anchors.leftMargin:     root._fw * 0.7
                anchors.verticalCenter: parent.verticalCenter
                width:                  root._fh * 1.8
                height:                 width
                radius:                 width / 2
                color:                  Qt.rgba(card._tagColor.r, card._tagColor.g, card._tagColor.b, 0.18)
                border.width:           2
                border.color:           card._tagColor
                QGCLabel {
                    anchors.centerIn:   parent
                    text:               card._veh ? card._veh.id : ""
                    color:              card._tagColor
                    font.bold:          true
                    font.family:        ScreenTools.fixedFontFamily
                }
            }

            MouseArea {
                id:             cardMouse
                anchors.fill:   parent
                hoverEnabled:   true
                cursorShape:    Qt.PointingHandCursor
                onClicked:      if (card._veh) root._mvm.activeVehicle = card._veh
            }

            Column {
                anchors.left:           tag.right
                anchors.leftMargin:     root._fw * 0.8
                anchors.right:          rightRow.left
                anchors.rightMargin:    root._fw * 0.5
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    spacing: root._fw * 0.6
                    QGCLabel {
                        text:       card._veh ? MLTheme.vehicleTypeName(card._veh) : ""
                        color:      MLTheme.text
                        font.bold:  true
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width:          stateText.implicitWidth + root._fw * 1.0
                        height:         stateText.implicitHeight + 2
                        radius:         height / 2
                        readonly property bool _on: !!card._veh && card._veh.armed
                        color:          card._lost ? "#3a1416" : (_on ? "#3a1416" : "#12301f")
                        border.width:   1
                        border.color:   card._lost || _on ? MLTheme.warning : MLTheme.ok
                        QGCLabel {
                            id:                 stateText
                            anchors.centerIn:   parent
                            text:               card._lost ? qsTr("통신 두절") : (parent._on ? qsTr("시동 ON") : qsTr("시동 OFF"))
                            color:              card._lost || parent._on ? MLTheme.warning : MLTheme.ok
                            font.pointSize:     ScreenTools.smallFontPointSize
                            font.bold:          true
                        }
                    }
                    QGCLabel {
                        visible:        card._isActive
                        anchors.verticalCenter: parent.verticalCenter
                        text:           qsTr("화면 표시 중")
                        color:          MLTheme.accent
                        font.pointSize: ScreenTools.smallFontPointSize
                    }
                }
                QGCLabel {
                    width:  parent.width
                    elide:  Text.ElideRight
                    text: {
                        var v = card._veh
                        if (!v) return ""
                        var alt = root._v(v.altitudeRelative), spd = root._v(v.groundSpeed)
                        return v.flightMode
                            + "  ·  " + (isNaN(alt) ? "—" : alt.toFixed(0) + " m")
                            + "  ·  " + (isNaN(spd) ? "—" : spd.toFixed(1) + " m/s")
                            + "  ·  " + qsTr("배터리") + " " + (isNaN(card._bat) ? "—" : Math.round(card._bat) + "%")
                    }
                    color:          MLTheme.label
                    font.pointSize: ScreenTools.smallFontPointSize
                }
            }

            Row {
                id:                     rightRow
                anchors.right:          parent.right
                anchors.rightMargin:    root._fw * 0.6
                anchors.verticalCenter: parent.verticalCenter
                spacing:                root._fw * 0.6

                // group-command check box
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width:          root._fh * 1.5
                    height:         width
                    radius:         root._fw * 0.3
                    readonly property bool _on: !!card._veh && root.isSelected(card._veh.id)
                    color:          _on ? MLTheme.accent : "transparent"
                    border.width:   1.5
                    border.color:   _on ? MLTheme.accent : MLTheme.lineStrong
                    QGCLabel {
                        anchors.centerIn:   parent
                        visible:            parent._on
                        text:               "✓"
                        color:              "#04161b"
                        font.bold:          true
                    }
                    MouseArea {
                        anchors.fill:   parent
                        anchors.margins: -root._fw * 0.4
                        cursorShape:    Qt.PointingHandCursor
                        onClicked: {
                            if (!card._veh) return
                            if (parent._on) root._mvm.deselectVehicle(card._veh.id)
                            else            root._mvm.selectVehicle(card._veh.id)
                        }
                    }
                    ToolTip.visible:    false
                }

                // plan a mission for this vehicle
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width:          planText.implicitWidth + root._fw * 1.8
                    height:         root._fh * 1.7
                    radius:         root._fw * 0.4
                    color:          planMouse.containsMouse ? "#1b3440" : MLTheme.panelRaised
                    border.width:   1
                    border.color:   planMouse.containsMouse ? MLTheme.accent : MLTheme.lineStrong
                    QGCLabel {
                        id:                 planText
                        anchors.centerIn:   parent
                        text:               qsTr("미션 계획")
                        color:              MLTheme.text
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                    }
                    MouseArea {
                        id:             planMouse
                        anchors.fill:   parent
                        hoverEnabled:   true
                        cursorShape:    Qt.PointingHandCursor
                        onClicked: {
                            if (!card._veh) return
                            root._mvm.activeVehicle = card._veh
                            if (typeof mainWindow !== "undefined") mainWindow.showPlanView()
                        }
                    }
                }
            }
        }
    }

    // ---- Group commands for the checked vehicles ------------------------------
    Column {
        id:             actions
        anchors.bottom: parent.bottom
        width:          parent.width
        spacing:        root._fh * 0.3

        Rectangle { width: parent.width; height: 1; color: MLTheme.line }

        Item {
            width:  parent.width
            height: root._fh * 1.3
            QGCLabel {
                anchors.left:           parent.left
                anchors.verticalCenter: parent.verticalCenter
                text:           root._selected.count === 0 ? qsTr("체크한 기체에 한꺼번에 명령") : qsTr("체크한 기체 %1대에 명령").arg(root._selected.count)
                color:          root._selected.count === 0 ? MLTheme.faint : MLTheme.text
                font.pointSize: ScreenTools.smallFontPointSize
                font.bold:      root._selected.count > 0
            }
            QGCLabel {
                anchors.right:          parent.right
                anchors.verticalCenter: parent.verticalCenter
                text:           root._selected.count === root._vehicles.count ? qsTr("전체 해제") : qsTr("전체 선택")
                color:          MLTheme.accent
                font.pointSize: ScreenTools.smallFontPointSize
                font.underline: allMouse.containsMouse
                MouseArea {
                    id:             allMouse
                    anchors.fill:   parent
                    hoverEnabled:   true
                    cursorShape:    Qt.PointingHandCursor
                    onClicked: {
                        if (root._selected.count === root._vehicles.count) {
                            root._mvm.deselectAllVehicles()
                        } else {
                            for (var i = 0; i < root._vehicles.count; i++) root._mvm.selectVehicle(root._vehicles.get(i).id)
                        }
                    }
                }
            }
        }

        Flow {
            width:      parent.width
            spacing:    root._fw * 0.5

            MLCommandButton {
                compact:        true
                text:           qsTr("시동")
                tone:           "normal"
                available:      root.anySelected(function(v) { return !v.armed && !v.flying })
                disabledReason: qsTr("시동을 걸 수 있는 체크된 기체가 없습니다")
                onClicked:      root.forSelected(function(v) { if (!v.armed && !v.flying) v.armed = true })
            }
            MLCommandButton {
                compact:        true
                text:           qsTr("시동 끄기")
                tone:           "caution"
                available:      root.anySelected(function(v) { return v.armed && !v.flying })
                disabledReason: qsTr("지상에서 시동이 걸린 체크된 기체가 없습니다")
                onClicked:      root.forSelected(function(v) { if (v.armed && !v.flying) v.armed = false })
            }
            MLCommandButton {
                compact:        true
                text:           qsTr("미션 시작")
                tone:           "go"
                available:      root._selected.count > 0
                disabledReason: qsTr("기체를 체크하세요")
                onClicked:      root.forSelected(function(v) { v.startMission() })
            }
            MLCommandButton {
                compact:        true
                text:           qsTr("일시정지")
                tone:           "caution"
                available:      root.anySelected(function(v) { return v.flying })
                disabledReason: qsTr("비행 중인 체크된 기체가 없습니다")
                onClicked:      root.forSelected(function(v) { if (v.flying) v.pauseVehicle() })
            }
        }
    }
}
