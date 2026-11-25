import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 목표 조정: change heading / altitude / speed of the selected vehicle in flight.
//
//   ┌ 목표 조정  HDG · ALT · SPD ─────────────────────── ✕ ┐
//   │ 방위  HDG      현재 352°                               │
//   │ [-10][-1]   [ 090 ° ]   [+1][+10]          [ 보내기 ] │
//   │   미션이 멈추고 이 방향으로 기수를 돌립니다             │
//   │ 고도  ALT ...                                          │
//   │ 속도  SPD ...      (미션을 유지한 채 속도만 바뀝니다)   │
//   └───────────────────────────────────────────────────────┘
//
// Commands use QGC's own vehicle calls, so each firmware gets what QGC sends:
//   speed    → MAV_CMD_DO_CHANGE_SPEED (PX4 and ArduPilot keep flying the mission)
//   altitude → guided altitude change (the mission pauses; resume from the command bar)
//   heading  → PX4 DO_REPOSITION yaw / ArduPilot CONDITION_YAW
// Every send needs two presses, like the command bar.
Rectangle {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    signal closeRequested()

    readonly property real _fw:         ScreenTools.defaultFontPixelWidth
    readonly property real _fh:         ScreenTools.defaultFontPixelHeight
    readonly property bool _has:        !!vehicle
    readonly property bool _commLost:   _has && vehicle.vehicleLinkManager.communicationLost
    readonly property bool _flying:     _has && vehicle.flying
    readonly property bool _airspeed:   _has && (vehicle.fixedWing || (vehicle.vtol && vehicle.vtolInFwdFlight))
    readonly property string _mode:     _has ? String(vehicle.flightMode) : ""
    readonly property bool _inMission:  _flying && /auto|mission|미션|자동/i.test(_mode) && !/rtl|return|land|복귀|착륙/i.test(_mode)
    readonly property bool _canGuide:   _has && vehicle.supports.guidedMode
    readonly property bool _canHeading: _has && vehicle.supports.changeHeading
    readonly property var  _mc:         globals.planMasterControllerFlyView ? globals.planMasterControllerFlyView.missionController : null
    readonly property bool _hasMission: !!_mc && _mc.visualItems && _mc.visualItems.count > 1
    readonly property bool _missionPaused: _flying && _hasMission && !_inMission && !/rtl|return|land|복귀|착륙/i.test(_mode)

    function _num(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined) ? NaN : v
    }
    readonly property real _hdg: _has ? _num(vehicle.heading) : NaN
    readonly property real _alt: _has ? _num(vehicle.altitudeRelative) : NaN
    readonly property real _spd: _has ? (_airspeed ? _num(vehicle.airSpeed) : _num(vehicle.groundSpeed)) : NaN

    property real hdgTarget: 0
    property real altTarget: 0
    property real spdTarget: 0

    function resetTargets() {
        hdgTarget = isNaN(_hdg) ? 0 : (Math.round(_hdg) + 360) % 360
        altTarget = isNaN(_alt) ? 0 : Math.round(_alt)
        spdTarget = isNaN(_spd) ? 0 : Math.round(_spd * 2) / 2
    }
    onVisibleChanged: if (visible) resetTargets()
    onVehicleChanged: resetTargets()

    // ---- Commands (also used by the SITL test hook below) -----------------
    function sendSpeed(metersPerSecond) {
        if (!_has) return
        if (_airspeed) vehicle.guidedModeChangeEquivalentAirspeedMetersSecond(metersPerSecond)
        else           vehicle.guidedModeChangeGroundSpeedMetersSecond(metersPerSecond)
    }
    function sendAltitude(targetRelMeters) {
        if (!_has || isNaN(_alt)) return
        vehicle.guidedModeChangeAltitude(targetRelMeters - _alt, false)
    }
    function sendHeading(degrees) {
        if (!_has || !vehicle.coordinate.isValid) return
        vehicle.guidedModeChangeHeading(vehicle.coordinate.atDistanceAndAzimuth(1000, degrees))
    }

    width:          _fw * 58
    height:         column.implicitHeight + _fh * 1.2
    radius:         _fw * 0.6
    color:          "#f20e151c"
    border.width:   1.5
    border.color:   MLTheme.accent

    // Swallow clicks so the map underneath does not react
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = true } }

    component StepButton: Rectangle {
        id: sb
        property string label
        signal pressed()
        width:          root._fw * 5.2
        height:         root._fh * 1.9
        radius:         root._fw * 0.4
        color:          sbMouse.pressed ? "#24404c" : (sbMouse.containsMouse ? "#1b2c36" : MLTheme.panelRaised)
        border.width:   1
        border.color:   sbMouse.containsMouse ? MLTheme.accent : MLTheme.lineStrong
        QGCLabel {
            anchors.centerIn:   parent
            text:               sb.label
            color:              MLTheme.text
            font.family:        ScreenTools.fixedFontFamily
            font.bold:          true
        }
        MouseArea {
            id:             sbMouse
            anchors.fill:   parent
            hoverEnabled:   true
            cursorShape:    Qt.PointingHandCursor
            onClicked:      sb.pressed()
            // hold to repeat
            onPressAndHold: repeat.start()
            onReleased:     repeat.stop()
        }
        Timer { id: repeat; interval: 120; repeat: true; onTriggered: sb.pressed() }
    }

    component SetRow: Column {
        id: row

        property string title
        property string tag
        property string unit
        property real   current:    NaN
        property real   target:     0
        property real   small:      1
        property real   big:        10
        property real   minValue:   0
        property real   maxValue:   9999
        property bool   wrap360:    false
        property int    digits:     0
        property bool   available:  true
        property string reason
        property string note
        property color  noteColor:  MLTheme.dim

        signal targetEdited(real value)
        signal send()

        function clampValue(v) {
            if (wrap360) return ((Math.round(v) % 360) + 360) % 360
            return Math.max(minValue, Math.min(maxValue, v))
        }
        function fmt(v) {
            if (isNaN(v)) return "—"
            if (wrap360) return ("00" + Math.round(v)).slice(-3)
            return v.toFixed(digits)
        }

        width:      parent.width
        spacing:    root._fh * 0.3

        Item {
            width:  parent.width
            height: rowTitle.implicitHeight
            QGCLabel {
                id:         rowTitle
                text:       row.title
                color:      MLTheme.text
                font.bold:  true
            }
            QGCLabel {
                anchors.left:       rowTitle.right
                anchors.leftMargin: root._fw * 0.6
                anchors.baseline:   rowTitle.baseline
                text:               row.tag
                color:              MLTheme.faint
                font.pointSize:     ScreenTools.smallFontPointSize
                font.letterSpacing: 1
            }
            QGCLabel {
                anchors.right:      parent.right
                anchors.baseline:   rowTitle.baseline
                text:               qsTr("현재  %1 %2").arg(row.fmt(row.current)).arg(row.unit)
                color:              MLTheme.label
                font.family:        ScreenTools.fixedFontFamily
            }
        }

        Row {
            spacing: root._fw * 0.5

            StepButton { label: "-" + row.big;   onPressed: row.targetEdited(row.clampValue(row.target - row.big)) }
            StepButton { label: "-" + row.small; onPressed: row.targetEdited(row.clampValue(row.target - row.small)) }

            Rectangle {
                width:          root._fw * 13
                height:         root._fh * 1.9
                radius:         root._fw * 0.4
                color:          "#0a1a12"
                border.width:   1.5
                border.color:   input.activeFocus ? "white" : MLTheme.ok

                TextInput {
                    id:                     input
                    anchors.left:           parent.left
                    anchors.right:          unitLabel.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin:    root._fw * 0.4
                    horizontalAlignment:    TextInput.AlignRight
                    text:                   row.fmt(row.target)
                    color:                  "white"
                    font.family:            ScreenTools.fixedFontFamily
                    font.pointSize:         ScreenTools.mediumFontPointSize
                    font.bold:              true
                    selectByMouse:          true
                    inputMethodHints:       Qt.ImhFormattedNumbersOnly
                    validator:              DoubleValidator { bottom: row.wrap360 ? 0 : row.minValue; top: row.wrap360 ? 360 : row.maxValue }
                    onEditingFinished: {
                        var v = parseFloat(text)
                        if (!isNaN(v)) row.targetEdited(row.clampValue(v))
                        text = Qt.binding(function() { return row.fmt(row.target) })
                    }
                }
                QGCLabel {
                    id:                     unitLabel
                    anchors.right:          parent.right
                    anchors.rightMargin:    root._fw * 0.7
                    anchors.verticalCenter: parent.verticalCenter
                    text:                   row.unit
                    color:                  MLTheme.dim
                }
            }

            StepButton { label: "+" + row.small; onPressed: row.targetEdited(row.clampValue(row.target + row.small)) }
            StepButton { label: "+" + row.big;   onPressed: row.targetEdited(row.clampValue(row.target + row.big)) }

            Item { width: root._fw * 0.6; height: 1 }

            MLCommandButton {
                compact:        true
                text:           qsTr("보내기")
                tone:           "go"
                available:      row.available
                disabledReason: row.reason
                onClicked:      row.send()
            }
        }

        QGCLabel {
            width:          parent.width
            wrapMode:       Text.WordWrap
            text:           row.available ? row.note : row.reason
            color:          row.available ? row.noteColor : MLTheme.faint
            font.pointSize: ScreenTools.smallFontPointSize
        }
    }

    function _reason(extra) {
        if (!_has)       return qsTr("기체가 연결되지 않았습니다")
        if (_commLost)   return qsTr("통신 두절 상태에서는 보낼 수 없습니다")
        if (!_flying)    return qsTr("비행 중에만 사용할 수 있습니다")
        if (!_canGuide)  return qsTr("이 기체는 지상국 유도 명령을 지원하지 않습니다")
        return extra
    }
    readonly property bool _ready: _has && !_commLost && _flying && _canGuide

    Column {
        id:                 column
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.top:        parent.top
        anchors.margins:    root._fw * 1.2
        anchors.topMargin:  root._fh * 0.5
        spacing:            root._fh * 0.6

        // Header
        Item {
            width:  parent.width
            height: root._fh * 1.6
            QGCLabel {
                id:                     head
                anchors.verticalCenter: parent.verticalCenter
                text:                   qsTr("목표 조정")
                color:                  MLTheme.text
                font.bold:              true
                font.pointSize:         ScreenTools.mediumFontPointSize
            }
            QGCLabel {
                anchors.left:           head.right
                anchors.leftMargin:     root._fw
                anchors.baseline:       head.baseline
                text:                   "HDG · ALT · SPD" + (root._has && QGroundControl.multiVehicleManager.vehicles.count > 1 ? qsTr("   ·   기체 %1").arg(root.vehicle.id) : "")
                color:                  MLTheme.faint
                font.pointSize:         ScreenTools.smallFontPointSize
                font.letterSpacing:     1
            }
            Rectangle {
                anchors.right:          parent.right
                anchors.verticalCenter: parent.verticalCenter
                width:                  root._fh * 1.6
                height:                 width
                radius:                 width / 2
                color:                  closeMouse.containsMouse ? MLTheme.panelRaised : "transparent"
                QGCLabel { anchors.centerIn: parent; text: "✕"; color: MLTheme.dim }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
            }
        }

        // Mission state banner
        Rectangle {
            width:      parent.width
            height:     bannerText.implicitHeight + root._fh * 0.6
            radius:     root._fw * 0.4
            visible:    root._flying
            color:      root._missionPaused ? "#33270f" : (root._inMission ? "#163325" : MLTheme.tile)
            border.width: 1
            border.color: root._missionPaused ? MLTheme.caution : (root._inMission ? "#2c7a4c" : MLTheme.line)
            QGCLabel {
                id:                 bannerText
                anchors.left:       parent.left
                anchors.right:      parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins:    root._fw
                wrapMode:           Text.WordWrap
                text: root._missionPaused ? qsTr("미션 멈춤 (%1) · 아래 명령 바의 [미션 재개]로 경로에 복귀합니다").arg(root._mode)
                                          : (root._inMission ? qsTr("미션 비행 중 · 속도는 미션을 유지한 채 바뀌고, 고도·방위를 보내면 미션이 멈춥니다")
                                                             : qsTr("현재 모드: %1").arg(root._mode))
                color:              root._missionPaused ? MLTheme.caution : (root._inMission ? MLTheme.ok : MLTheme.label)
                font.pointSize:     ScreenTools.smallFontPointSize
                font.bold:          true
            }
        }

        SetRow {
            title:          qsTr("방위")
            tag:            "HDG"
            unit:           "°"
            current:        root._hdg
            target:         root.hdgTarget
            wrap360:        true
            available:      root._ready && root._canHeading
            reason:         root._reason(qsTr("이 기체 종류는 방위 지정 명령을 지원하지 않습니다 (고정익 등)"))
            note:           root._inMission ? qsTr("보내면 미션이 멈추고 이 방향으로 기수를 돌립니다") : qsTr("이 방향으로 기수를 돌립니다")
            noteColor:      root._inMission ? MLTheme.caution : MLTheme.dim
            onTargetEdited: function(value) { root.hdgTarget = value }
            onSend:         root.sendHeading(root.hdgTarget)
        }

        Rectangle { width: parent.width; height: 1; color: MLTheme.line }

        SetRow {
            title:          qsTr("고도")
            tag:            "ALT"
            unit:           "m"
            current:        root._alt
            target:         root.altTarget
            minValue:       2
            maxValue:       1000
            available:      root._ready
            reason:         root._reason("")
            note:           root._inMission ? qsTr("보내면 미션이 멈추고 그 자리에서 이 고도로 이동합니다 (이륙 지점 기준)") : qsTr("그 자리에서 이 고도로 이동합니다 (이륙 지점 기준)")
            noteColor:      root._inMission ? MLTheme.caution : MLTheme.dim
            onTargetEdited: function(value) { root.altTarget = value }
            onSend:         root.sendAltitude(root.altTarget)
        }

        Rectangle { width: parent.width; height: 1; color: MLTheme.line }

        SetRow {
            title:          root._airspeed ? qsTr("대기속도") : qsTr("속도")
            tag:            root._airspeed ? "IAS" : "SPD"
            unit:           "m/s"
            current:        root._spd
            target:         root.spdTarget
            small:          0.5
            big:            5
            digits:         1
            minValue:       0.5
            maxValue:       60
            available:      root._has && !root._commLost && root._flying
            reason:         root._reason("")
            note:           root._inMission ? qsTr("미션을 유지한 채 다음 구간부터 이 속도로 비행합니다") : qsTr("최대 수평 속도를 이 값으로 바꿉니다")
            noteColor:      root._inMission ? MLTheme.ok : MLTheme.dim
            onTargetEdited: function(value) { root.spdTarget = value }
            onSend:         root.sendSpeed(root.spdTarget)
        }
    }

    // ---- SITL test hook ----------------------------------------------------
    // With ML_TEST_SETPOINTS=1 the CI flies a scripted check: once the vehicle
    // is flying its mission it calls the same send functions as the buttons
    // (speed, then altitude, then heading) and an external MAVLink monitor
    // checks that the aircraft responds.
    readonly property bool _testMode: typeof mlTestSetpoints !== "undefined" && mlTestSetpoints
    property int _testStep: 0
    Timer {
        id:         testTimer
        interval:   1000
        repeat:     true
        running:    root._testMode
        property int ticks: 0
        onTriggered: {
            if (root._testStep === 0) {
                if (root._inMission) { ticks++ } else { ticks = 0 }
                if (ticks >= 12) { console.log("MLTEST speed 2.5"); root.sendSpeed(2.5); root._testStep = 1; ticks = 0 }
            } else if (root._testStep === 1) {
                if (++ticks >= 25) { console.log("MLTEST altitude +15 from", root._alt); root.sendAltitude(root._alt + 15); root._testStep = 2; ticks = 0 }
            } else if (root._testStep === 2) {
                if (++ticks >= 25) { console.log("MLTEST heading 90"); root.sendHeading(90); root._testStep = 3; ticks = 0 }
            } else if (root._testStep === 3) {
                if (++ticks >= 20) { console.log("MLTEST done"); root._testStep = 4; stop() }
            }
        }
    }
}
