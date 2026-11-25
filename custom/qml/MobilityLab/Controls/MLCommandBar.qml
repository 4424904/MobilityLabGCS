import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Bottom command bar of the console (full width).
//
//   ● 연결 ─ ● 준비 ─ ○ 무장 ─ ○ 비행 ─ ○ 착륙 │ [ARM] [이륙] [미션 시작] │ 14:35:42 │ [비상 정지]
//   비행 전 점검을 마치면 ARM 하세요            │                         │ 날짜     │
//
// The progress strip shows where the flight is; the buttons change with it
// (on the ground: arm/takeoff/mission, in the air: pause/RTL/land), so only
// commands that make sense now are offered, using QGC's own rules for when
// each is allowed. Safety: every button needs two presses (the first arms it
// for 3 s, see MLCommandButton), then the command is sent. Takeoff then opens
// QGC's altitude slider so the takeoff height can be chosen. The emergency button needs a 2 s hold: engine kill on aircraft
// that report an engine (EFI), otherwise QGC's motor emergency stop.
Rectangle {
    id: root

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

    // Send a guided action straight away (the two-press button is the confirmation)
    function execute(action) {
        if (!_guided || !_vehicle) return
        _guided.executeAction(action, null, 0, false)
    }

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

    color:          MLTheme.panelSolid
    radius:         ScreenTools.defaultFontPixelWidth * 0.5
    border.color:   MLTheme.line
    border.width:   1

    implicitHeight: ScreenTools.defaultFontPixelHeight * 3.2 + _pad * 1.6

    // ---- Phase strip + next step (left) ----------------------------------
    Column {
        id:                     steps
        anchors.left:           parent.left
        anchors.leftMargin:     root._pad * 1.2
        anchors.verticalCenter: parent.verticalCenter
        width:                  Math.max(stepRow.implicitWidth, ScreenTools.defaultFontPixelWidth * 34)
        spacing:                ScreenTools.defaultFontPixelHeight * 0.3

        Row {
            id:         stepRow
            spacing:    0

            Repeater {
                model: [ qsTr("연결"), qsTr("준비"), qsTr("무장"), qsTr("비행"), qsTr("착륙") ]

                Row {
                    spacing: ScreenTools.defaultFontPixelWidth * 0.45

                    Rectangle {
                        visible:                index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width:                  ScreenTools.defaultFontPixelWidth * 1.6
                        height:                 2
                        color:                  index <= root._phase ? MLTheme.accent : MLTheme.line
                    }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width:                  ScreenTools.defaultFontPixelHeight * 1.0
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
                        rightPadding:           ScreenTools.defaultFontPixelWidth * 0.45
                    }
                }
            }
        }

        QGCLabel {
            width:          parent.width
            elide:          Text.ElideRight
            text:           root.nextStep()
            color:          root._commLost ? MLTheme.warning : MLTheme.accent
            font.bold:      true
        }
    }

    Rectangle {
        id:                     divider1
        anchors.left:           steps.right
        anchors.leftMargin:     root._pad * 1.4
        anchors.verticalCenter: parent.verticalCenter
        width:                  1
        height:                 parent.height * 0.6
        color:                  MLTheme.line
    }

    // ---- Clock (right, before the emergency button) -----------------------
    Column {
        id:                     clock
        anchors.right:          killButton.left
        anchors.rightMargin:    root._pad * 1.6
        anchors.verticalCenter: parent.verticalCenter
        visible:                root.width > ScreenTools.defaultFontPixelWidth * 150

        property date now: new Date()
        Timer { interval: 1000; running: clock.visible; repeat: true; onTriggered: clock.now = new Date() }

        QGCLabel {
            anchors.right:  parent.right
            text:           Qt.formatTime(clock.now, "hh:mm:ss")
            color:          MLTheme.text
            font.family:    ScreenTools.fixedFontFamily
            font.pointSize: ScreenTools.mediumFontPointSize
            font.bold:      true
        }
        QGCLabel {
            anchors.right:  parent.right
            text:           Qt.formatDate(clock.now, "yyyy-MM-dd")
            color:          MLTheme.dim
            font.family:    ScreenTools.fixedFontFamily
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    // ---- Buttons (middle) --------------------------------------------------
    Row {
        id:                     buttons
        anchors.left:           divider1.right
        anchors.leftMargin:     root._pad * 1.4
        anchors.verticalCenter: parent.verticalCenter
        spacing:                root._pad * 0.7

        // --- on the ground ---
        MLCommandButton {
            visible:        !root._flying
            text:           root._armed ? qsTr("무장 해제") : qsTr("ARM")
            subText:        root._armed ? "DISARM" : qsTr("무장")
            iconSource:     "/MobilityLab/icons/arm.svg"
            tone:           root._armed ? "caution" : "normal"
            available:      root.show("showArm") || root.show("showDisarm")
            disabledReason: root.reason(qsTr("ARM 조건 미충족 · 상단 상태 표시줄 확인"))
            onClicked:      root.execute(root._armed ? root._guided.actionDisarm : root._guided.actionArm)
        }
        MLCommandButton {
            visible:        !root._flying
            text:           qsTr("이륙")
            subText:        qsTr("TAKEOFF · 고도 선택")
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
            onClicked:      root.execute(root._guided.actionStartMission)
        }

        // --- in the air ---
        MLCommandButton {
            visible:        root._flying && root.show("showContinueMission")
            text:           qsTr("미션 재개")
            subText:        "CONTINUE"
            iconSource:     "/MobilityLab/icons/play.svg"
            tone:           "go"
            onClicked:      root.execute(root._guided.actionContinueMission)
        }
        MLCommandButton {
            visible:        root._flying && !root.show("showContinueMission")
            text:           qsTr("일시정지")
            subText:        "PAUSE"
            iconSource:     "/MobilityLab/icons/pause.svg"
            tone:           "caution"
            available:      root.show("showPause")
            disabledReason: root.reason(qsTr("이미 정지 상태이거나 지원하지 않습니다"))
            onClicked:      if (root._vehicle) root._vehicle.pauseVehicle()
        }
        MLCommandButton {
            visible:        root._flying
            text:           qsTr("복귀")
            subText:        "RTL"
            iconSource:     "/MobilityLab/icons/rtl.svg"
            tone:           "active"
            available:      root.show("showRTL")
            disabledReason: root.reason(qsTr("이미 복귀 중입니다"))
            onClicked:      root.execute(root._guided.actionRTL)
        }
        MLCommandButton {
            visible:        root._flying
            text:           qsTr("착륙")
            subText:        "LAND"
            iconSource:     "/MobilityLab/icons/land.svg"
            tone:           "caution"
            available:      root.show("showLand")
            disabledReason: root.reason(qsTr("이미 착륙 중입니다"))
            onClicked:      root.execute(root._guided.actionLand)
        }

    }

    MLHoldButton {
        id:                     killButton
        anchors.right:          parent.right
        anchors.rightMargin:    root._pad * 1.2
        anchors.verticalCenter: parent.verticalCenter
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
