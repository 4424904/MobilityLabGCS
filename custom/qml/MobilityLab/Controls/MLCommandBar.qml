import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Bottom command bar. Every command goes through QGC's guided action
// controller, so each one still asks for the standard slide-to-confirm and
// uses QGC's own rules for when it is allowed. Engine kill uses a 2 s hold.
Rectangle {
    id: root

    property real maxWidth: ScreenTools.defaultFontPixelWidth * 200

    readonly property var  _vehicle:    QGroundControl.multiVehicleManager.activeVehicle
    readonly property var  _guided:     globals.guidedControllerFlyView
    readonly property bool _connected:  !!_vehicle
    readonly property bool _commLost:   _connected && _vehicle.vehicleLinkManager.communicationLost
    readonly property bool _armed:      _connected && _vehicle.armed
    readonly property bool _flying:     _connected && _vehicle.flying
    readonly property real _pad:        ScreenTools.defaultFontPixelWidth

    readonly property int  _mavCmdDoEngineControl:  223     // MAV_CMD_DO_ENGINE_CONTROL
    readonly property int  _autopilotCompId:        1       // MAV_COMP_ID_AUTOPILOT1

    function show(flagName) {
        return _connected && !_commLost && !!_guided && !!_guided[flagName]
    }

    function reason(defaultText) {
        if (!_connected) return qsTr("기체가 연결되지 않았습니다")
        if (_commLost)   return qsTr("통신 두절 상태에서는 명령을 보낼 수 없습니다")
        return defaultText
    }

    function nextStep() {
        if (!_connected)        return qsTr("기체 연결 대기 · 통신 링크를 확인하세요")
        if (_commLost)          return qsTr("통신 두절 · 기체 Failsafe 동작을 확인하세요")
        if (!_armed) {
            if (show("showArm"))    return qsTr("비행 전 점검 후 ARM")
            return qsTr("ARM 불가 · 상단 상태 표시의 점검 항목을 확인하세요")
        }
        if (!_flying)           return qsTr("ARM 완료 · 이륙 또는 미션 시작")
        return qsTr("비행 중 · ") + _vehicle.flightMode
    }

    color:          MLTheme.panel
    radius:         ScreenTools.defaultFontPixelWidth * 0.6
    border.color:   MLTheme.line
    border.width:   1

    implicitWidth:  Math.min(maxWidth, flow.usedWidth + _pad * 2)
    implicitHeight: flow.implicitHeight + _pad * 2
    width:          implicitWidth
    height:         implicitHeight

    Flow {
        id:                 flow
        anchors.left:       parent.left
        anchors.top:        parent.top
        anchors.margins:    root._pad
        width:              root.maxWidth - root._pad * 2
        spacing:            root._pad * 0.8

        // Width actually used by the laid-out buttons (Flow's own implicitWidth is read-only)
        property real usedWidth: 0
        onPositioningComplete: {
            var w = 0
            for (var i = 0; i < children.length; i++) {
                var c = children[i]
                if (c.visible) w = Math.max(w, c.x + c.width)
            }
            usedWidth = w
        }

        MLCommandButton {
            text:           root._armed ? qsTr("시동 해제") : qsTr("ARM")
            subText:        root._armed ? "DISARM" : qsTr("무장")
            iconSource:     "/MobilityLab/icons/arm.svg"
            tone:           root._armed ? "caution" : "normal"
            available:      root.show("showArm") || root.show("showDisarm")
            disabledReason: root.reason(root._flying ? qsTr("비행 중에는 해제할 수 없습니다") : qsTr("ARM 조건 미충족"))
            onClicked:      root._guided.confirmAction(root._armed ? root._guided.actionDisarm : root._guided.actionArm)
        }

        MLCommandButton {
            text:           qsTr("이륙")
            subText:        "TAKEOFF"
            iconSource:     "/MobilityLab/icons/takeoff.svg"
            tone:           "go"
            available:      root.show("showTakeoff")
            disabledReason: root.reason(root._flying ? qsTr("이미 비행 중입니다") : qsTr("이륙 조건 미충족"))
            onClicked:      root._guided.confirmAction(root._guided.actionTakeoff)
        }

        MLCommandButton {
            readonly property bool _continue: root.show("showContinueMission")
            text:           _continue ? qsTr("미션 재개") : qsTr("미션 시작")
            subText:        _continue ? "CONTINUE" : "START"
            iconSource:     "/MobilityLab/icons/play.svg"
            tone:           "go"
            available:      root.show("showStartMission") || _continue
            disabledReason: root.reason(qsTr("업로드된 미션이 없거나 시작 조건 미충족"))
            onClicked:      root._guided.confirmAction(_continue ? root._guided.actionContinueMission : root._guided.actionStartMission)
        }

        MLCommandButton {
            text:           qsTr("일시정지")
            subText:        "PAUSE"
            iconSource:     "/MobilityLab/icons/pause.svg"
            tone:           "caution"
            available:      root.show("showPause")
            disabledReason: root.reason(qsTr("비행 중일 때 사용"))
            onClicked:      root._guided.confirmAction(root._guided.actionPause)
        }

        MLCommandButton {
            text:           qsTr("복귀")
            subText:        "RTL"
            iconSource:     "/MobilityLab/icons/rtl.svg"
            tone:           "active"
            available:      root.show("showRTL")
            disabledReason: root.reason(qsTr("비행 중일 때 사용"))
            onClicked:      root._guided.confirmAction(root._guided.actionRTL)
        }

        MLCommandButton {
            text:           qsTr("착륙")
            subText:        "LAND"
            iconSource:     "/MobilityLab/icons/land.svg"
            tone:           "caution"
            available:      root.show("showLand")
            disabledReason: root.reason(qsTr("비행 중일 때 사용"))
            onClicked:      root._guided.confirmAction(root._guided.actionLand)
        }

        // Next-step guidance
        Rectangle {
            width:          ScreenTools.defaultFontPixelWidth * 26
            height:         ScreenTools.defaultFontPixelHeight * 3.2
            radius:         ScreenTools.defaultFontPixelWidth * 0.4
            color:          "#0f1a1e"

            Rectangle {
                width:  Math.max(3, ScreenTools.defaultFontPixelWidth * 0.35)
                height: parent.height
                color:  root._commLost ? MLTheme.warning : MLTheme.accent
            }
            Column {
                anchors.left:           parent.left
                anchors.right:          parent.right
                anchors.leftMargin:     ScreenTools.defaultFontPixelWidth * 1.2
                anchors.rightMargin:    ScreenTools.defaultFontPixelWidth * 0.6
                anchors.verticalCenter: parent.verticalCenter
                QGCLabel {
                    text:           qsTr("다음 단계")
                    color:          MLTheme.dim
                    font.pointSize: ScreenTools.smallFontPointSize
                }
                QGCLabel {
                    width:          parent.width
                    text:           root.nextStep()
                    color:          MLTheme.text
                    font.bold:      true
                    wrapMode:       Text.WordWrap
                    maximumLineCount: 2
                    elide:          Text.ElideRight
                }
            }
        }

        MLHoldButton {
            text:           qsTr("엔진 비상정지")
            subText:        qsTr("2초간 누르기")
            iconSource:     "/MobilityLab/icons/kill.svg"
            available:      root._connected && !root._commLost
            disabledReason: root.reason("")
            onActivated: {
                // param1 = 0: stop engine
                root._vehicle.sendCommand(root._autopilotCompId, root._mavCmdDoEngineControl, true, 0, 0, 0, 0, 0, 0, 0)
            }
        }
    }
}
