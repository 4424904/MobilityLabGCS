import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Bottom command dock.
//
//   ● 연결 ── ● 준비 ── ○ 무장 ── ○ 비행 ── ○ 착륙      다음: 비행 전 점검 후 ARM
//   [ ARM ] [ 이륙 ] [ 미션 시작 ]                          [ 비상 정지 (2초) ]
//
// The progress strip shows where the flight is; the buttons change with it
// (on the ground: arm/takeoff/mission, in the air: pause/RTL/land), so only
// commands that make sense now are offered. Every command still goes through
// QGC's guided-action slide-to-confirm and QGC's own rules for when it is
// allowed. The emergency button needs a 2 s hold: engine kill on aircraft
// that report an engine (EFI), otherwise QGC's motor emergency stop.
Rectangle {
    id: root

    property real maxWidth: ScreenTools.defaultFontPixelWidth * 200

    readonly property var  _vehicle:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property var  _guided:     globals.guidedControllerFlyView
    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property bool _connected:  !!_vehicle
    readonly property bool _commLost:   _connected && _vehicle.vehicleLinkManager.communicationLost
    readonly property bool _armed:      _connected && _vehicle.armed
    readonly property bool _flying:     _connected && _vehicle.flying
    readonly property bool _hasEngine:  !!_t && _t.seenKeys["eng.rpm"] === true
    readonly property string _mode:     _connected ? String(_vehicle.flightMode) : ""
    readonly property bool _landing:    _flying && /land|착륙|rtl|return|복귀/i.test(_mode)
    readonly property real _pad:        ScreenTools.defaultFontPixelWidth * 1.1

    readonly property int  _mavCmdDoEngineControl:  223     // MAV_CMD_DO_ENGINE_CONTROL
    readonly property int  _autopilotCompId:        1       // MAV_COMP_ID_AUTOPILOT1

    // 0 연결, 1 준비, 2 무장, 3 비행, 4 착륙
    readonly property int _phase: !_connected ? 0 : (!_armed ? 1 : (!_flying ? 2 : (_landing ? 4 : 3)))

    function show(flagName) {
        return _connected && !_commLost && !!_guided && !!_guided[flagName]
    }

    function reason(defaultText) {
        if (!_connected) return qsTr("기체가 연결되지 않았습니다")
        if (_commLost)   return qsTr("통신 두절 상태에서는 명령을 보낼 수 없습니다")
        return defaultText
    }

    function nextStep() {
        if (!_connected)    return qsTr("기체 연결을 기다리는 중 · 통신 링크를 확인하세요")
        if (_commLost)      return qsTr("통신 두절 · 기체 Failsafe 동작을 확인하세요")
        if (!_armed)        return show("showArm") ? qsTr("비행 전 점검을 마치면 ARM 하세요")
                                                   : qsTr("ARM 불가 · 위쪽 상태 표시줄의 점검 항목을 확인하세요")
        if (!_flying)       return qsTr("이륙하거나 미션을 시작하세요")
        if (_landing)       return qsTr("%1 · 착지 후 무장 해제를 확인하세요").arg(_mode)
        return qsTr("비행 중 · %1").arg(_mode)
    }

    color:          MLTheme.panel
    radius:         MLTheme.radius
    border.color:   MLTheme.line
    border.width:   1

    implicitWidth:  Math.min(maxWidth, Math.max(steps.implicitWidth, buttons.usedWidth) + _pad * 2)
    implicitHeight: steps.height + buttons.height + _pad * 2.6
    width:          implicitWidth
    height:         implicitHeight

    // ---- Progress strip + next step --------------------------------------
    Item {
        id:                 steps
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.margins:    root._pad
        height:             ScreenTools.defaultFontPixelHeight * 1.6
        implicitWidth:      stepRow.implicitWidth + ScreenTools.defaultFontPixelWidth * 34

        Row {
            id:                     stepRow
            anchors.left:           parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing:                0

            Repeater {
                model: [ qsTr("연결"), qsTr("준비"), qsTr("무장"), qsTr("비행"), qsTr("착륙") ]

                Row {
                    spacing: ScreenTools.defaultFontPixelWidth * 0.5

                    Rectangle {
                        visible:                index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width:                  ScreenTools.defaultFontPixelWidth * 2.2
                        height:                 2
                        color:                  index <= root._phase ? MLTheme.accent : MLTheme.line
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width:                  ScreenTools.defaultFontPixelHeight * 1.1
                        height:                 width

                        Rectangle {
                            visible:            index === root._phase
                            anchors.fill:       parent
                            radius:             width / 2
                            color:              "transparent"
                            border.width:       1.5
                            border.color:       root._commLost ? MLTheme.warning : MLTheme.accent
                            opacity:            0.5
                        }
                        Rectangle {
                            anchors.centerIn:   parent
                            width:              parent.width * 0.6
                            height:             width
                            radius:             width / 2
                            color:              index < root._phase ? MLTheme.accent : (index === root._phase ? (root._commLost ? MLTheme.warning : MLTheme.accent) : "transparent")
                            border.width:       index === root._phase ? 0 : 1.5
                            border.color:       index < root._phase ? MLTheme.accent : MLTheme.lineStrong
                        }
                    }
                    QGCLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text:                   modelData
                        color:                  index === root._phase ? MLTheme.text : (index < root._phase ? MLTheme.label : MLTheme.faint)
                        font.bold:              index === root._phase
                        font.pointSize:         ScreenTools.smallFontPointSize
                        rightPadding:           ScreenTools.defaultFontPixelWidth * 0.5
                    }
                }
            }
        }

        QGCLabel {
            anchors.left:           stepRow.right
            anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 2
            anchors.right:          parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment:    Text.AlignRight
            elide:                  Text.ElideRight
            text:                   root.nextStep()
            color:                  root._commLost ? MLTheme.warning : MLTheme.text
            font.pointSize:         ScreenTools.smallFontPointSize
        }
    }

    // ---- Buttons ---------------------------------------------------------
    Flow {
        id:                 buttons
        anchors.left:       parent.left
        anchors.top:        steps.bottom
        anchors.leftMargin: root._pad
        anchors.topMargin:  root._pad * 0.6
        width:              root.maxWidth - root._pad * 2
        spacing:            root._pad * 0.7

        // Width actually used by the laid-out buttons (Flow's own implicitWidth is read-only)
        property real usedWidth: 0
        onPositioningComplete: {
            var w = 0
            for (var i = 0; i < children.length; i++) {
                var c = children[i]
                if (c.visible && c.width > 0) w = Math.max(w, c.x + c.width)
            }
            usedWidth = w
        }

        // --- on the ground ---
        MLCommandButton {
            visible:        !root._flying
            text:           root._armed ? qsTr("무장 해제") : qsTr("ARM")
            subText:        root._armed ? "DISARM" : qsTr("무장")
            iconSource:     "/MobilityLab/icons/arm.svg"
            tone:           root._armed ? "caution" : "normal"
            available:      root.show("showArm") || root.show("showDisarm")
            disabledReason: root.reason(qsTr("ARM 조건 미충족 · 상단 상태 표시줄 확인"))
            onClicked:      root._guided.confirmAction(root._armed ? root._guided.actionDisarm : root._guided.actionArm)
        }
        MLCommandButton {
            visible:        !root._flying
            text:           qsTr("이륙")
            subText:        "TAKEOFF"
            iconSource:     "/MobilityLab/icons/takeoff.svg"
            tone:           "go"
            available:      root.show("showTakeoff")
            disabledReason: root.reason(qsTr("이륙 조건 미충족"))
            onClicked:      root._guided.confirmAction(root._guided.actionTakeoff)
        }
        MLCommandButton {
            visible:        !root._flying
            text:           qsTr("미션 시작")
            subText:        "START"
            iconSource:     "/MobilityLab/icons/play.svg"
            tone:           "go"
            available:      root.show("showStartMission")
            disabledReason: root.reason(qsTr("업로드된 미션이 없거나 시작 조건 미충족"))
            onClicked:      root._guided.confirmAction(root._guided.actionStartMission)
        }

        // --- in the air ---
        MLCommandButton {
            visible:        root._flying && root.show("showContinueMission")
            text:           qsTr("미션 재개")
            subText:        "CONTINUE"
            iconSource:     "/MobilityLab/icons/play.svg"
            tone:           "go"
            onClicked:      root._guided.confirmAction(root._guided.actionContinueMission)
        }
        MLCommandButton {
            visible:        root._flying && !root.show("showContinueMission")
            text:           qsTr("일시정지")
            subText:        "PAUSE"
            iconSource:     "/MobilityLab/icons/pause.svg"
            tone:           "caution"
            available:      root.show("showPause")
            disabledReason: root.reason(qsTr("이미 정지 상태이거나 지원하지 않습니다"))
            onClicked:      root._guided.confirmAction(root._guided.actionPause)
        }
        MLCommandButton {
            visible:        root._flying
            text:           qsTr("복귀")
            subText:        "RTL"
            iconSource:     "/MobilityLab/icons/rtl.svg"
            tone:           "active"
            available:      root.show("showRTL")
            disabledReason: root.reason(qsTr("이미 복귀 중입니다"))
            onClicked:      root._guided.confirmAction(root._guided.actionRTL)
        }
        MLCommandButton {
            visible:        root._flying
            text:           qsTr("착륙")
            subText:        "LAND"
            iconSource:     "/MobilityLab/icons/land.svg"
            tone:           "caution"
            available:      root.show("showLand")
            disabledReason: root.reason(qsTr("이미 착륙 중입니다"))
            onClicked:      root._guided.confirmAction(root._guided.actionLand)
        }

        Item {
            width:  ScreenTools.defaultFontPixelWidth * 2
            height: 1
        }

        MLHoldButton {
            text:           root._hasEngine ? qsTr("엔진 비상정지") : qsTr("비상 정지")
            subText:        qsTr("2초간 누르기")
            iconSource:     "/MobilityLab/icons/kill.svg"
            available:      root._connected && !root._commLost && (root._hasEngine || root._armed)
            disabledReason: root.reason(root._hasEngine ? "" : qsTr("무장 상태에서만 사용합니다"))
            tooltipText:    root._hasEngine ? qsTr("엔진을 즉시 정지합니다 (MAV_CMD_DO_ENGINE_CONTROL).")
                                            : qsTr("모터를 즉시 정지합니다. 비행 중이면 추락합니다.")
            onActivated: {
                if (!root._vehicle) return
                if (root._hasEngine) {
                    root._vehicle.sendCommand(root._autopilotCompId, root._mavCmdDoEngineControl, true, 0, 0, 0, 0, 0, 0, 0)
                } else {
                    root._vehicle.emergencyStop()
                }
            }
        }
    }
}
