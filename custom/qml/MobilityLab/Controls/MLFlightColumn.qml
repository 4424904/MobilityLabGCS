import QtQuick

import QGroundControl
import QGroundControl.Controls

// Left console column:
//   flight mode annunciator (SPD · LAT · VERT · MODE)
//   primary flight display
//   key numbers (V/S, AGL, TRK, home, next waypoint, ETE)
//   link / navigation bars
Rectangle {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property real u:           MLTheme.u
    readonly property bool _has:        !!vehicle
    readonly property var  _mc:         globals.planMasterControllerFlyView ? globals.planMasterControllerFlyView.missionController : null
    readonly property int  _cur:        _mc ? _mc.currentMissionIndex : -1
    readonly property var  _curItem:    (_mc && _cur > 0 && _cur < _mc.visualItems.count) ? _mc.visualItems.get(_cur) : null
    readonly property string _mode:     _has ? String(vehicle.flightMode) : ""
    readonly property bool _flying:     _has && vehicle.flying
    readonly property bool _rtl:        /rtl|return|복귀/i.test(_mode)
    readonly property bool _land:       /land|착륙/i.test(_mode)
    readonly property bool _mission:    _flying && /auto|mission|미션/i.test(_mode) && !_rtl && !_land
    readonly property bool _hold:       _flying && /hold|loiter|guided|brake|position|대기|위치/i.test(_mode)

    function fv(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined || v === null) ? NaN : Number(v)
    }

    readonly property real _wpAlt: {
        var it = _curItem
        if (!it || !it.isSimpleItem || !it.altitude) return NaN
        return Number(it.altitude.rawValue)
    }

    color: MLTheme.panelSolid

    // ---- Flight mode annunciator -------------------------------------------
    Row {
        id:     fma
        width:  parent.width
        height: 50 * u

        component Cell: Item {
            property string label
            property string value
            property color  valueColor: MLTheme.active
            property bool   last:       false
            width:  fma.width / 4
            height: fma.height
            MLText {
                x: 12 * u; y: 8 * u
                text:               parent.label
                color:              MLTheme.dim
                font.pixelSize:     MLTheme.fsLabel
                font.letterSpacing: 0.7 * u
            }
            Text {
                x: 12 * u; y: 24 * u
                width:              parent.width - 16 * u
                elide:              Text.ElideRight
                text:               parent.value
                color:              parent.valueColor
                font.family:        MLTheme.mono
                font.pixelSize:     MLTheme.fsValue
            }
            Rectangle { visible: !parent.last; anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
        }

        Cell {
            label:      "SPD"
            value:      !root._flying ? "—" : (!isNaN(MLState.targetSpeed) ? "SPD " + MLState.targetSpeed.toFixed(1) : (root._mission ? "MISSION" : (root._rtl ? "RTL" : "HOLD")))
            valueColor: root._flying ? MLTheme.active : MLTheme.faint
        }
        Cell {
            label:      "LAT"
            value:      !root._flying ? "—" : (root._mission ? "WPT " + Math.max(0, root._cur) : (root._rtl ? "RTL" : (root._land ? "LAND" : (!isNaN(MLState.targetHeading) ? "HDG " + ("00" + Math.round(MLState.targetHeading)).slice(-3) : "HOLD"))))
            valueColor: root._flying ? MLTheme.active : MLTheme.faint
        }
        Cell {
            label:      "VERT"
            value:      !root._flying ? "—" : (!isNaN(MLState.targetAlt) ? "ALT " + Math.round(MLState.targetAlt) : (root._mission && !isNaN(root._wpAlt) ? "ALT " + Math.round(root._wpAlt) : (root._land ? "DESC" : "ALT HOLD")))
            valueColor: root._flying ? MLTheme.active : MLTheme.faint
        }
        Cell {
            label:      "MODE"
            value:      root._has ? root._mode : "—"
            valueColor: MLTheme.text
            last:       true
        }
    }
    Rectangle { id: fmaRule; anchors.top: fma.bottom; width: parent.width; height: 1; color: MLTheme.line }

    // ---- PFD ------------------------------------------------------------------
    readonly property real _belowHeight: numbers.height + (links.visible ? links.height : 0)
    MLPfd {
        id:             pfd
        anchors.top:    fmaRule.bottom
        anchors.topMargin: 4 * u
        width:          parent.width
        height:         Math.max(240 * u, Math.min(400 * u * width / (460 * u), root.height - fma.height - root._belowHeight - 8 * u))
        vehicle:        root.vehicle
        targetSpeed:    MLState.targetSpeed
        targetAlt:      !isNaN(MLState.targetAlt) ? MLState.targetAlt : (root._mission ? root._wpAlt : NaN)
        targetHeading:  !isNaN(MLState.targetHeading) ? MLState.targetHeading : (root._mission ? root.fv(root._has ? root.vehicle.headingToNextWP : null) : NaN)
    }

    // ---- Key numbers ---------------------------------------------------------
    Grid {
        id:             numbers
        anchors.top:    pfd.bottom
        anchors.topMargin: 4 * u
        width:          parent.width
        columns:        3

        component NumCell: Item {
            property string label
            property string value
            property string unit
            property color  valueColor: MLTheme.text
            property bool   rightRule:  true
            width:  numbers.width / 3
            height: 66 * u
            Rectangle { width: parent.width; height: 1; color: MLTheme.line }
            Rectangle { visible: parent.rightRule; anchors.right: parent.right; width: 1; height: parent.height; color: MLTheme.line }
            MLText { x: 16 * u; y: 12 * u; text: parent.label; color: MLTheme.dim; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.7 * u }
            MLNum  { x: 16 * u; y: 28 * u; text: parent.value; unit: parent.unit; size: MLTheme.fsBig; color: parent.valueColor }
        }

        readonly property real _vs:   root._has ? root.fv(root.vehicle.climbRate) : NaN
        readonly property real _agl:  root._has ? root.fv(root.vehicle.altitudeAboveTerr) : NaN
        readonly property real _trk:  root._has ? root.fv(root.vehicle.gps.courseOverGround) : NaN
        readonly property var  _home: MLTheme.distance(root._has ? root.fv(root.vehicle.distanceToHome) : NaN)
        readonly property real _next: root._has ? root.fv(root.vehicle.distanceToNextWP) : NaN
        readonly property var  _nextD: MLTheme.distance(root._mission && _next > 0 ? _next : NaN)
        readonly property real _gs:   root._has ? root.fv(root.vehicle.groundSpeed) : NaN

        NumCell { label: "V/S"; value: isNaN(numbers._vs) ? "—" : (numbers._vs >= 0 ? "+" : "") + numbers._vs.toFixed(1); unit: "m/s" }
        NumCell { label: "AGL"; value: isNaN(numbers._agl) ? "—" : numbers._agl.toFixed(0); unit: isNaN(numbers._agl) ? "" : "m" }
        NumCell { label: "TRK"; value: isNaN(numbers._trk) ? "—" : ("00" + Math.round(numbers._trk)).slice(-3); unit: isNaN(numbers._trk) ? "" : "°"; rightRule: false }
        NumCell { label: qsTr("홈 거리"); value: numbers._home.v; unit: numbers._home.u }
        NumCell { label: root._mission ? qsTr("WPT %1까지").arg(root._cur) : qsTr("다음 경유점"); value: numbers._nextD.v; unit: numbers._nextD.u }
        NumCell {
            label:      "ETE"
            value:      (root._mission && numbers._gs > 0.5 && numbers._next > 0) ? MLTheme.duration(numbers._next / numbers._gs) : "—"
            rightRule:  false
        }
    }

    // ---- Link / navigation bars ---------------------------------------------
    Column {
        id:             links
        anchors.top:    numbers.bottom
        width:          parent.width
        visible:        root.height - fma.height - 240 * u - numbers.height > height
        height:         implicitHeight

        MLSection { width: parent.width; title: qsTr("링크 · 항법") }

        component BarRow: Item {
            property string label
            property string value
            property real   frac:   0          // 0..1
            property color  barColor: MLTheme.label
            width:  links.width
            height: 30 * u
            MLText { x: 20 * u; anchors.verticalCenter: parent.verticalCenter; width: 92 * u; text: parent.label; color: MLTheme.label; font.pixelSize: MLTheme.fsSmall }
            Row {
                x:          116 * u
                anchors.verticalCenter: parent.verticalCenter
                spacing:    2 * u
                Repeater {
                    model: 20
                    Rectangle {
                        width:  ((links.width - 116 * u - 112 * u) - 19 * 2 * u) / 20
                        height: 8 * u
                        color:  index < Math.round(parent.parent.frac * 20) ? parent.parent.barColor : String(MLTheme.line)
                    }
                }
            }
            Text {
                anchors.right:          parent.right
                anchors.rightMargin:    20 * u
                anchors.verticalCenter: parent.verticalCenter
                text:                   parent.value
                color:                  MLTheme.text
                font.family:            MLTheme.mono
                font.pixelSize:         MLTheme.fsBody
            }
            Rectangle { anchors.bottom: parent.bottom; x: 20 * u; width: parent.width - 40 * u; height: 1; color: MLTheme.hair }
        }

        readonly property bool _lost:  root._has && root.vehicle.vehicleLinkManager.communicationLost
        readonly property real _rssi:  root._has ? root.fv(root.vehicle.radioStatus.lrssi) : NaN
        readonly property real _rc:    root._has ? root.fv(root.vehicle.rcRSSI) : NaN
        readonly property real _lock:  root._has ? root.fv(root.vehicle.gps.lock) : NaN
        readonly property real _sats:  root._has ? root.fv(root.vehicle.gps.count) : NaN
        readonly property real _hdop:  root._has ? root.fv(root.vehicle.gps.hdop) : NaN
        readonly property real _vib:   root._has ? Math.max(root.fv(root.vehicle.vibration.xAxis), root.fv(root.vehicle.vibration.yAxis), root.fv(root.vehicle.vibration.zAxis)) : NaN

        BarRow {
            label:      qsTr("텔레메트리")
            readonly property bool _hasRssi: !isNaN(links._rssi) && links._rssi !== 0
            value:      !root._has ? "—" : (links._lost ? qsTr("두절") : (_hasRssi ? links._rssi.toFixed(0) + " dBm" : qsTr("연결")))
            frac:       !root._has || links._lost ? 0 : (_hasRssi ? Math.max(0, Math.min(1, (links._rssi + 110) / 60)) : 1)
            barColor:   links._lost ? MLTheme.warning : MLTheme.label
        }
        BarRow {
            label:      qsTr("조종기")
            readonly property bool _ok: !isNaN(links._rc) && links._rc >= 0 && links._rc <= 100
            value:      _ok ? links._rc.toFixed(0) + " %" : "—"
            frac:       _ok ? links._rc / 100 : 0
            barColor:   _ok && links._rc < 30 ? MLTheme.caution : MLTheme.label
        }
        BarRow {
            label:      "GPS"
            value:      isNaN(links._lock) ? "—" : (links._lock >= 6 ? "RTK" : (links._lock === 5 ? "RTK F" : (links._lock >= 3 ? "3D" : (links._lock === 2 ? "2D" : qsTr("없음"))))) + (isNaN(links._sats) ? "" : " · " + links._sats.toFixed(0))
            frac:       isNaN(links._sats) ? 0 : Math.min(1, links._sats / 20)
            barColor:   !isNaN(links._lock) && links._lock < 3 ? MLTheme.warning : MLTheme.label
        }
        BarRow {
            label:      "HDOP"
            value:      isNaN(links._hdop) ? "—" : links._hdop.toFixed(1)
            frac:       isNaN(links._hdop) ? 0 : Math.max(0, Math.min(1, 1 - (links._hdop - 0.5) / 4))
            barColor:   !isNaN(links._hdop) && links._hdop > 2.5 ? MLTheme.caution : MLTheme.label
        }
        BarRow {
            label:      qsTr("진동")
            value:      isNaN(links._vib) ? "—" : links._vib.toFixed(0) + " m/s²"
            frac:       isNaN(links._vib) ? 0 : Math.min(1, links._vib / 90)
            barColor:   isNaN(links._vib) ? MLTheme.label : (links._vib > 60 ? MLTheme.warning : (links._vib > 30 ? MLTheme.caution : MLTheme.label))
        }
    }

    // ---- Event log: fills whatever height is left --------------------------
    MLEventLog {
        anchors.top:    links.visible ? links.bottom : numbers.bottom
        anchors.bottom: parent.bottom
        width:          parent.width
        visible:        height > 90 * u
    }

    MLPanelChrome { radius: root.radius }
}
