import QtQuick
import QtQuick.Controls

import QGroundControl
import QGroundControl.Controls

// 목표 조정: change altitude / speed / heading of the selected vehicle in flight.
//
//   ┌ 목표 조정 · UAV 01              [미션 유지 | 멈추고 변경] ┐
//   │ 경로는 그대로 두고 남은 경유점의 고도·속도와 기수만 바꿉니다   │
//   │ ALT   83 m    [ − |    95 m    | + ]   [보내기]           │
//   │ SPD   14.2    [ − |  10.0 m/s  | + ]   [보내기]           │
//   │ HDG   352°    [ − |    045°    | + ]   [보내기]           │
//   └──────────────────────────────────────────────────────────┘
//
// 미션 유지 (mission keeps running):
//   ALT → remaining waypoints get the new altitude, the mission is re-uploaded
//         and the current waypoint restored
//   SPD → MAV_CMD_DO_CHANGE_SPEED
//   HDG → region of interest 5 km out on that bearing: the nose points there
//         while the aircraft keeps flying the route ("기수 자동" clears it)
// 멈추고 변경 (mission pauses, resume from the command bar):
//   ALT/HDG → ArduPilot: QGC guided calls; PX4: DO_REPOSITION at the current
//             position (an altitude-only reposition would keep flying to the
//             current waypoint)
// Every send needs two presses. Values sent become magenta targets on the PFD.
Rectangle {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle
    signal closeRequested()

    readonly property real u:           MLTheme.u
    readonly property bool _has:        !!vehicle
    readonly property bool _commLost:   _has && vehicle.vehicleLinkManager.communicationLost
    readonly property bool _flying:     _has && vehicle.flying
    readonly property bool _airspeed:   _has && (vehicle.fixedWing || (vehicle.vtol && vehicle.vtolInFwdFlight))
    readonly property string _mode:     _has ? String(vehicle.flightMode) : ""
    readonly property bool _rtlLand:    /rtl|return|land|복귀|착륙/i.test(_mode)
    readonly property bool _inMission:  _flying && /auto|mission|미션|자동/i.test(_mode) && !_rtlLand
    readonly property bool _canGuide:   _has && vehicle.supports.guidedMode
    readonly property bool _canHeading: _has && vehicle.supports.changeHeading
    readonly property var  _pmc:        globals.planMasterControllerFlyView
    readonly property var  _mc:         _pmc ? _pmc.missionController : null
    readonly property bool _hasMission: !!_mc && _mc.visualItems && _mc.visualItems.count > 1
    readonly property bool _missionPaused: _flying && _hasMission && !_inMission && !_rtlLand

    // keep = 미션 유지, otherwise 멈추고 변경
    property bool keepMission: true
    readonly property bool _keep: keepMission && _inMission && _hasMission

    function _num(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }
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
    // Each target follows the live value until the operator touches that row,
    // so the panel always opens showing where the aircraft is now.
    property bool _altEdited: false
    property bool _spdEdited: false
    property bool _hdgEdited: false
    function _follow() {
        if (!_altEdited && !isNaN(_alt)) altTarget = Math.max(0, Math.round(_alt))
        if (!_spdEdited && !isNaN(_spd)) spdTarget = Math.round(_spd * 2) / 2
        if (!_hdgEdited && !isNaN(_hdg)) hdgTarget = (Math.round(_hdg) + 360) % 360
    }
    function _clearEdits() { _altEdited = _spdEdited = _hdgEdited = false; _follow() }
    onVisibleChanged: { _clearEdits(); if (visible) keepMission = _inMission }
    onVehicleChanged: _clearEdits()
    on_AltChanged:    _follow()
    on_SpdChanged:    _follow()
    on_HdgChanged:    _follow()
    on_FlyingChanged: _clearEdits()

    // ---- commands -------------------------------------------------------------
    function sendSpeed(mps) {
        if (!_has) return
        if (_airspeed) vehicle.guidedModeChangeEquivalentAirspeedMetersSecond(mps)
        else           vehicle.guidedModeChangeGroundSpeedMetersSecond(mps)
        MLState.targetSpeed = mps
    }

    // 미션 유지: rewrite the remaining waypoints' altitude and re-upload
    property int _restoreSeq: -1
    function sendAltitudeKeep(targetRel) {
        if (!_mc || !_pmc || _pmc.syncInProgress) return false
        var cur = Math.max(1, _mc.currentMissionIndex), items = _mc.visualItems, changed = 0
        var curItem = items.get(cur)
        for (var i = cur; i < items.count; i++) {
            var it = items.get(i)
            if (!it || !it.isSimpleItem || !it.specifiesCoordinate || it.isLandCommand || it.isTakeoffItem || !it.altitude) continue
            if (it.altitudeFrame !== QGroundControl.AltitudeFrameRelative) continue
            it.altitude.rawValue = targetRel
            changed++
        }
        if (changed === 0) return false
        _restoreSeq = curItem ? curItem.sequenceNumber : -1
        console.log("MLTEST mission altitude", targetRel, "items", changed, "restore seq", _restoreSeq)
        _pmc.sendToVehicle()
        MLState.targetAlt = targetRel
        return true
    }
    // After the upload the autopilot may restart the mission from the first item
    // (PX4 does, once it has stored the new mission), so the current waypoint is
    // set again a moment later, and once more if the vehicle still disagrees.
    property int _pendingSeq: -1
    Connections {
        target: root._pmc
        function onSyncInProgressChanged() {
            if (root._pmc && !root._pmc.syncInProgress && root._restoreSeq >= 0 && root._has) {
                console.log("MLTEST mission uploaded, will set current", root._restoreSeq)
                root._pendingSeq = root._restoreSeq
                root._restoreSeq = -1
                restoreTimer.attempt = 0
                restoreTimer.restart()
            }
        }
    }
    Timer {
        id: restoreTimer
        property int attempt: 0
        interval: 1500
        onTriggered: {
            if (!root._has || root._pendingSeq < 0) return
            var curIdx = root._mc ? root._mc.currentMissionIndex : -1
            var curItem = (root._mc && curIdx > 0 && curIdx < root._mc.visualItems.count) ? root._mc.visualItems.get(curIdx) : null
            var curSeq = curItem ? curItem.sequenceNumber : -1
            if (attempt > 0 && curSeq === root._pendingSeq) { root._pendingSeq = -1; return }
            console.log("MLTEST set current", root._pendingSeq, "vehicle at", curSeq, "attempt", attempt)
            root.vehicle.setCurrentMissionSequence(root._pendingSeq)
            if (++attempt < 3) restart(); else root._pendingSeq = -1
        }
    }

    // 멈추고 변경 (PX4: reposition here; ArduPilot: QGC guided calls)
    readonly property int _mavCmdDoReposition: 192
    property real _px4HoldAmsl: NaN
    on_InMissionChanged: if (_inMission) _px4HoldAmsl = NaN
    function _px4Reposition(yawDeg, amsl) {
        var c = vehicle.coordinate
        if (!c.isValid || isNaN(amsl)) return false
        vehicle.sendCommand(1, _mavCmdDoReposition, true, -1, 1, 0,
                            isNaN(yawDeg) ? NaN : yawDeg * Math.PI / 180, c.latitude, c.longitude, amsl)
        return true
    }
    function sendAltitudeHold(targetRel) {
        if (!_has || isNaN(_alt)) return
        MLState.targetAlt = targetRel
        if (vehicle.px4Firmware && vehicle.homePosition.isValid && !isNaN(vehicle.homePosition.altitude)) {
            _px4HoldAmsl = vehicle.homePosition.altitude + targetRel
            if (_px4Reposition(NaN, _px4HoldAmsl)) return
        }
        vehicle.guidedModeChangeAltitude(targetRel - _alt, false)
    }
    function sendHeadingHold(deg) {
        if (!_has || !vehicle.coordinate.isValid) return
        MLState.targetHeading = deg
        if (vehicle.px4Firmware) {
            var amsl = !isNaN(_px4HoldAmsl) ? _px4HoldAmsl : _num(vehicle.altitudeAMSL)
            if (_px4Reposition(deg, amsl)) return
        }
        vehicle.guidedModeChangeHeading(vehicle.coordinate.atDistanceAndAzimuth(1000, deg))
    }
    // ROI sent directly (MAV_CMD_DO_SET_ROI_LOCATION / _NONE): QGC's own ROI call
    // waits for a terrain lookup on PX4, which the heading use does not need.
    readonly property int _mavCmdDoSetRoiLocation: 195
    readonly property int _mavCmdDoSetRoiNone:     197
    function sendHeadingKeep(deg) {
        if (!_has || !vehicle.coordinate.isValid) return
        var p = vehicle.coordinate.atDistanceAndAzimuth(5000, deg)
        var amsl = _num(vehicle.altitudeAMSL)
        vehicle.sendCommand(1, _mavCmdDoSetRoiLocation, true, 0, 0, 0, 0, p.latitude, p.longitude, isNaN(amsl) ? 0 : amsl)
        MLState.targetHeading = deg
    }
    function clearHeading() {
        if (_has) vehicle.sendCommand(1, _mavCmdDoSetRoiNone, true, 0, 0, 0, 0, 0, 0, 0)
        MLState.targetHeading = NaN
    }

    function sendAltitude(t) { if (_keep) { if (!sendAltitudeKeep(t)) sendAltitudeHold(t) } else sendAltitudeHold(t) }
    function sendHeading(d)  { if (_keep) sendHeadingKeep(d); else sendHeadingHold(d) }

    function _reason(extra) {
        if (!_has)       return qsTr("기체가 연결되지 않았습니다")
        if (_commLost)   return qsTr("통신 두절 상태에서는 보낼 수 없습니다")
        if (!_flying)    return qsTr("비행 중에만 사용할 수 있습니다")
        if (!_canGuide)  return qsTr("이 기체는 지상국 유도 명령을 지원하지 않습니다")
        return extra
    }
    readonly property bool _ready: _has && !_commLost && _flying && _canGuide

    // ---- look -----------------------------------------------------------------
    width:          420 * u
    height:         col.implicitHeight
    radius:         8 * u
    color:          MLTheme.panel
    border.width:   1
    border.color:   "#232931"

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: function(wheel) { wheel.accepted = true } }

    component Seg: Rectangle {
        id: seg
        property string label
        property bool   on: false
        signal picked()
        width:  segText.implicitWidth + 22 * MLTheme.u
        height: 28 * MLTheme.u
        color:  on ? "#1A2129" : (segMouse.containsMouse ? "#11161B" : "transparent")
        MLText { id: segText; anchors.centerIn: parent; text: seg.label; color: seg.on ? MLTheme.bright : MLTheme.dim; font.pixelSize: MLTheme.fsSmall }
        MouseArea { id: segMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked() }
    }

    component StepBtn: Rectangle {
        id: b
        property string glyph
        signal fire()
        width:  40 * MLTheme.u
        color:  bm.pressed ? "#1A2129" : (bm.containsMouse ? "#151B21" : "#10151A")
        MLText { anchors.centerIn: parent; text: b.glyph; color: MLTheme.label; font.pixelSize: 15 * MLTheme.u }
        MouseArea {
            id: bm; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: b.fire()
            onPressAndHold: rep.start()
            onReleased: rep.stop()
            onCanceled: rep.stop()
        }
        Timer { id: rep; interval: 110; repeat: true; onTriggered: b.fire() }
    }

    component Row3: Item {
        id: r3
        property string key
        property string now
        property string target
        property bool   available: true
        property string reason
        signal minus()
        signal plus()
        signal edited(real v)
        signal send()
        height: 46 * MLTheme.u
        Text { x: 14 * MLTheme.u; anchors.verticalCenter: parent.verticalCenter; text: r3.key; color: MLTheme.label; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }
        Text { x: 58 * MLTheme.u; width: 66 * MLTheme.u; anchors.verticalCenter: parent.verticalCenter; text: r3.now; color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsBody; elide: Text.ElideRight }
        Rectangle {
            x: 128 * MLTheme.u; width: parent.width - 128 * MLTheme.u - 96 * MLTheme.u; height: 36 * MLTheme.u
            anchors.verticalCenter: parent.verticalCenter
            radius: 5 * MLTheme.u; color: MLTheme.bg; border.width: 1; border.color: input.activeFocus ? MLTheme.target : "#232931"; clip: true
            StepBtn { id: mBtn; anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: 1; glyph: "−"; onFire: r3.minus() }
            StepBtn { id: pBtn; anchors.right: parent.right; anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.margins: 1; glyph: "+"; onFire: r3.plus() }
            TextInput {
                id:                     input
                anchors.left:           mBtn.right
                anchors.right:          pBtn.left
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment:    TextInput.AlignHCenter
                text:                   r3.target
                color:                  MLTheme.target
                font.family:            MLTheme.mono
                font.pixelSize:         16 * MLTheme.u
                selectByMouse:          true
                inputMethodHints:       Qt.ImhFormattedNumbersOnly
                onEditingFinished: {
                    var v = parseFloat(text)
                    if (!isNaN(v)) r3.edited(v)
                    text = Qt.binding(function() { return r3.target })
                }
            }
        }
        MLCommandButton {
            anchors.right: parent.right; anchors.rightMargin: 14 * MLTheme.u; anchors.verticalCenter: parent.verticalCenter
            width: 72 * MLTheme.u; compact: true
            text: qsTr("보내기")
            available: r3.available
            disabledReason: r3.reason
            onClicked: r3.send()
        }
    }

    function _wrap(v) { return ((Math.round(v) % 360) + 360) % 360 }

    Column {
        id:     col
        width:  parent.width

        // header
        Item {
            width:  parent.width
            height: 48 * u
            MLText {
                anchors.left: parent.left; anchors.leftMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("목표 조정") + (root._has ? "  ·  UAV " + ("0" + root.vehicle.id).slice(-2) : "")
                color: MLTheme.text; font.pixelSize: MLTheme.fsSmall; font.weight: Font.DemiBold; font.letterSpacing: 1.2 * u
            }
            Rectangle {
                anchors.right: closeBtn.left; anchors.rightMargin: 8 * u; anchors.verticalCenter: parent.verticalCenter
                width: segRow.implicitWidth + 2; height: 30 * u; radius: 5 * u; color: "transparent"; border.width: 1; border.color: "#232931"; clip: true
                Row {
                    id: segRow; x: 1; y: 1
                    Seg { label: qsTr("미션 유지"); on: root.keepMission; onPicked: root.keepMission = true }
                    Rectangle { width: 1; height: 28 * u; color: "#232931" }
                    Seg { label: qsTr("멈추고 변경"); on: !root.keepMission; onPicked: root.keepMission = false }
                }
            }
            Rectangle {
                id: closeBtn
                anchors.right: parent.right; anchors.rightMargin: 8 * u; anchors.verticalCenter: parent.verticalCenter
                width: 28 * u; height: width; radius: 4 * u
                color: closeMouse.containsMouse ? "#151B21" : "transparent"
                MLText { anchors.centerIn: parent; text: "✕"; color: MLTheme.dim; font.pixelSize: MLTheme.fsSmall }
                MouseArea { id: closeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: MLTheme.line }
        }

        // what will happen
        Item {
            width:  parent.width
            height: note.implicitHeight + 16 * u
            MLText {
                id: note
                x: 14 * u; y: 10 * u; width: parent.width - 28 * u
                wrapMode: Text.WordWrap; elide: Text.ElideNone
                font.pixelSize: MLTheme.fsSmall
                color: root._missionPaused ? MLTheme.caution : MLTheme.dim
                text: !root._flying ? qsTr("비행 중에만 사용할 수 있습니다")
                      : root._missionPaused ? qsTr("미션 멈춤 (%1) · 명령 바의 [미션 재개]로 경로에 복귀합니다").arg(root._mode)
                      : root._keep ? qsTr("경로는 그대로 두고 남은 경유점의 고도, 속도, 기수만 바꿉니다")
                      : (root.keepMission && !root._hasMission) ? qsTr("기체에 미션이 없어 멈추고 변경합니다")
                      : qsTr("보내면 미션이 멈추고 그 자리에서 고도·기수를 바꿉니다")
            }
        }

        Row3 {
            width: col.width
            key: "ALT"
            now: isNaN(root._alt) ? "—" : root._alt.toFixed(0) + " m"
            target: root.altTarget.toFixed(0) + " m"
            available: root._ready
            reason: root._reason("")
            onMinus: { root._altEdited = true; root.altTarget = Math.max(2, root.altTarget - 1) }
            onPlus:  { root._altEdited = true; root.altTarget = Math.min(1000, root.altTarget + 1) }
            onEdited: function(v) { root._altEdited = true; root.altTarget = Math.max(2, Math.min(1000, Math.round(v))) }
            onSend:  root.sendAltitude(root.altTarget)
        }
        Row3 {
            width: col.width
            key: root._airspeed ? "IAS" : "SPD"
            now: isNaN(root._spd) ? "—" : root._spd.toFixed(1)
            target: root.spdTarget.toFixed(1) + " m/s"
            available: root._has && !root._commLost && root._flying
            reason: root._reason("")
            onMinus: { root._spdEdited = true; root.spdTarget = Math.max(0.5, root.spdTarget - 0.5) }
            onPlus:  { root._spdEdited = true; root.spdTarget = Math.min(60, root.spdTarget + 0.5) }
            onEdited: function(v) { root._spdEdited = true; root.spdTarget = Math.max(0.5, Math.min(60, Math.round(v * 2) / 2)) }
            onSend:  root.sendSpeed(root.spdTarget)
        }
        Row3 {
            width: col.width
            key: "HDG"
            now: isNaN(root._hdg) ? "—" : ("00" + Math.round((root._hdg + 360) % 360)).slice(-3) + "°"
            target: ("00" + Math.round(root.hdgTarget)).slice(-3) + "°"
            available: root._ready && (root._keep || root._canHeading)
            reason: root._reason(qsTr("이 기체 종류는 방위 지정 명령을 지원하지 않습니다 (고정익 등)"))
            onMinus: { root._hdgEdited = true; root.hdgTarget = root._wrap(root.hdgTarget - 1) }
            onPlus:  { root._hdgEdited = true; root.hdgTarget = root._wrap(root.hdgTarget + 1) }
            onEdited: function(v) { root._hdgEdited = true; root.hdgTarget = root._wrap(v) }
            onSend:  root.sendHeading(root.hdgTarget)
        }

        Item {
            width:  parent.width
            height: 30 * u
            visible: !isNaN(MLState.targetHeading) && root._keep
            MLText {
                anchors.right: parent.right; anchors.rightMargin: 14 * u; anchors.verticalCenter: parent.verticalCenter
                text: qsTr("기수 자동으로 되돌리기"); color: "#9FD8F2"; font.pixelSize: MLTheme.fsSmall
                font.underline: autoMouse.containsMouse
                MouseArea { id: autoMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clearHeading() }
            }
        }
        Item { width: 1; height: 6 * u }
    }

    // ---- SITL test hook (CI only, ML_TEST_SETPOINTS=1) -------------------------
    // Once airborne it loads the mission from the vehicle and then calls the same
    // functions the buttons use: speed (keep), altitude (keep), heading (keep),
    // then altitude with the mission paused. tools/sitl_check.py watches the
    // aircraft on a second MAVLink link.
    readonly property bool _testMode: typeof mlTestSetpoints !== "undefined" && mlTestSetpoints
    property int _testStep: 0
    Timer {
        interval:   1000
        repeat:     true
        running:    root._testMode
        property int ticks: 0
        onTriggered: {
            if (root._testStep === 0) {
                if (root._flying && root._alt > 15) ticks++; else ticks = 0
                if (ticks === 5 && typeof mlTools !== "undefined") { console.log("MLTEST load mission"); mlTools.reloadMission(root.vehicle) }
                if (ticks >= 15) { console.log("MLTEST speed 2.5 (keep), mission items", root._mc ? root._mc.visualItems.count : -1); root.keepMission = true; root.sendSpeed(2.5); root._testStep = 1; ticks = 0 }
            } else if (root._testStep === 1) {
                if (++ticks >= 25) { console.log("MLTEST altitude keep", Math.round(root._alt + 15), "inMission", root._inMission, "keep", root._keep); root.keepMission = true; root.sendAltitude(Math.round(root._alt + 15)); root._testStep = 2; ticks = 0 }
            } else if (root._testStep === 2) {
                if (++ticks >= 60) { console.log("MLTEST heading keep 225"); root.keepMission = true; root.sendHeading(225); root._testStep = 3; ticks = 0 }
            } else if (root._testStep === 3) {
                if (++ticks >= 30) { console.log("MLTEST altitude hold +10 from", root._alt); root.keepMission = false; root.sendAltitude(Math.round(root._alt + 10)); root._testStep = 4; ticks = 0 }
            } else if (root._testStep === 4) {
                if (++ticks >= 25) { console.log("MLTEST done"); root._testStep = 5; stop() }
            }
        }
    }
}
