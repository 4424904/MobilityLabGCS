import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// Bottom command bar of the console (full width).
//
//   ━━ ━━ ━━ ━━ ──   │ [일시정지][복귀 RTL][착륙][목표 조정] │ 안내 │      [엔진 비상정지 HOLD 2s]
//   연결 준비 시동 비행 착륙
//   다음 할 일 …
//
// The phase strip shows where the flight is; the buttons change with it
// (ground: 시동/이륙/미션 시작, air: 일시정지 or 미션 재개/복귀/착륙/목표 조정),
// using QGC's own rules for when each is allowed. Every command needs two
// presses (MLCommandButton); takeoff then opens QGC's altitude slider. The
// emergency button needs a 2 s hold: engine kill on aircraft that report an
// engine (EFI), otherwise QGC's motor emergency stop.
Rectangle {
    id: root

    property real leftWidth:    460 * MLTheme.u
    property real rightWidth:   440 * MLTheme.u

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
    readonly property real u:           MLTheme.u

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
        if (!_armed)        return show("showArm") ? qsTr("비행 전 점검을 마치면 시동을 거세요")
                                                   : qsTr("시동 불가 · 위쪽 상태 표시줄의 점검 항목을 확인하세요")
        if (!_flying)       return qsTr("이륙하거나 미션을 시작하세요")
        if (_landing)       return qsTr("%1 · 착지 후 시동 끄기를 확인하세요").arg(_mode)
        return qsTr("비행 중 · %1").arg(_mode)
    }

    color:          MLTheme.panelSolid
    implicitHeight: 84 * u

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: MLTheme.line }

    // ---- phase strip + next step -------------------------------------------
    Item {
        id:     phaseBlock
        width:  root.leftWidth
        height: parent.height
        Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
        Column {
            anchors.left:           parent.left
            anchors.right:          parent.right
            anchors.margins:        20 * u
            anchors.verticalCenter: parent.verticalCenter
            spacing:                8 * u
            Row {
                width:      parent.width
                spacing:    4 * u
                Repeater {
                    model: [ qsTr("연결"), qsTr("준비"), qsTr("시동"), qsTr("비행"), qsTr("착륙") ]
                    Column {
                        width:      (parent.width - 16 * u) / 5
                        spacing:    6 * u
                        Rectangle {
                            width:  parent.width
                            height: 3 * u
                            color:  index < root._phase ? "#4A535C" : (index === root._phase ? (root._commLost ? MLTheme.warning : MLTheme.accent) : "#161C22")
                        }
                        MLText {
                            text:               modelData
                            color:              index === root._phase ? MLTheme.bright : (index < root._phase ? MLTheme.dim : "#3A424A")
                            font.pixelSize:     MLTheme.fsLabel
                            font.letterSpacing: 0.7 * u
                            font.weight:        index === root._phase ? Font.DemiBold : Font.Normal
                        }
                    }
                }
            }
            MLText {
                width:          parent.width
                text:           root.nextStep()
                color:          root._commLost ? MLTheme.warning : "#9FD8F2"
                font.pixelSize: MLTheme.fsSmall
            }
        }
    }

    // ---- commands ------------------------------------------------------------
    Row {
        id:                     buttons
        anchors.left:           phaseBlock.right
        anchors.leftMargin:     20 * u
        anchors.verticalCenter: parent.verticalCenter
        spacing:                10 * u

        // --- on the ground ---
        MLCommandButton {
            visible:        !root._flying
            text:           root._armed ? qsTr("시동 끄기") : qsTr("시동 걸기")
            subText:        root._armed ? "DISARM" : "ARM"
            tone:           root._armed ? "caution" : "normal"
            available:      root.show("showArm") || root.show("showDisarm")
            disabledReason: root.reason(qsTr("시동 조건 미충족 · 상단 상태 표시 확인"))
            onClicked:      root.execute(root._armed ? root._guided.actionDisarm : root._guided.actionArm)
        }
        MLCommandButton {
            visible:        !root._flying
            text:           qsTr("이륙")
            subText:        "TAKEOFF"
            tone:           "go"
            available:      root.show("showTakeoff")
            disabledReason: root.reason(qsTr("이륙 조건 미충족"))
            onClicked:      root._guided.confirmAction(root._guided.actionTakeoff)
        }
        MLCommandButton {
            visible:        !root._flying
            text:           qsTr("미션 시작")
            subText:        "START"
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
            tone:           "go"
            onClicked:      root.execute(root._guided.actionContinueMission)
        }
        MLCommandButton {
            visible:        root._flying && !root.show("showContinueMission")
            text:           qsTr("일시정지")
            subText:        "PAUSE"
            tone:           "caution"
            available:      root.show("showPause")
            disabledReason: root.reason(qsTr("이미 정지 상태이거나 지원하지 않습니다"))
            onClicked:      if (root._vehicle) root._vehicle.pauseVehicle()
        }
        MLCommandButton {
            visible:        root._flying
            text:           qsTr("복귀")
            subText:        "RTL"
            available:      root.show("showRTL")
            disabledReason: root.reason(qsTr("이미 복귀 중입니다"))
            onClicked:      root.execute(root._guided.actionRTL)
        }
        MLCommandButton {
            visible:        root._flying
            text:           qsTr("착륙")
            subText:        "LAND"
            available:      root.show("showLand")
            disabledReason: root.reason(qsTr("이미 착륙 중입니다"))
            onClicked:      root.execute(root._guided.actionLand)
        }
        MLCommandButton {
            visible:        root._flying
            twoStep:        false
            text:           qsTr("목표 조정")
            subText:        "ALT · SPD · HDG"
            tone:           "active"
            selected:       MLState.setpointsOpen
            available:      root._connected && !root._commLost
            disabledReason: root.reason("")
            onClicked:      MLState.setpointsOpen = !MLState.setpointsOpen
        }
    }

    MLText {
        anchors.left:           buttons.right
        anchors.leftMargin:     20 * u
        anchors.right:          killBlock.left
        anchors.rightMargin:    20 * u
        anchors.verticalCenter: parent.verticalCenter
        text:                   qsTr("명령은 두 번 눌러 실행 · 비상정지는 2초 누름")
        color:                  MLTheme.faint
        font.pixelSize:         MLTheme.fsLabel
        font.letterSpacing:     0.5 * u
    }

    // ---- emergency stop ------------------------------------------------------
    Item {
        id:             killBlock
        anchors.right:  parent.right
        width:          root.rightWidth
        height:         parent.height
        MLHoldButton {
            anchors.right:          parent.right
            anchors.rightMargin:    20 * u
            anchors.verticalCenter: parent.verticalCenter
            width:                  Math.min(220 * u, parent.width - 40 * u)
            text:           root._hasEngine ? qsTr("엔진 비상정지") : qsTr("비상 정지")
            available:      root._connected && !root._commLost && (root._hasEngine || root._armed)
            disabledReason: root.reason(root._hasEngine ? "" : qsTr("시동이 걸린 상태에서만 사용합니다"))
            tooltipText:    root._hasEngine ? qsTr("엔진을 즉시 정지합니다 (MAV_CMD_DO_ENGINE_CONTROL).")
                                            : qsTr("모터를 즉시 정지합니다. 비행 중이면 추락합니다.")
            onActivated: {
                if (!root._vehicle) return
                MLState.command(root._hasEngine ? qsTr("엔진 비상정지") : qsTr("비상 정지"))
                if (root._hasEngine) {
                    root._vehicle.sendCommand(root._autopilotCompId, root._mavCmdDoEngineControl, true, 0, 0, 0, 0, 0, 0, 0)
                } else {
                    root._vehicle.emergencyStop()
                }
            }
        }
    }
}
