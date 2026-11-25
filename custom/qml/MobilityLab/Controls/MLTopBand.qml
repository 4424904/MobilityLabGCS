import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Top band of the single-screen console, one row of panels:
//
//   [ 비행 계기 PFD ][ 추진 계통 ][ 전원 · 연료 ][ 항법 · 통신 ][ 경고 · 알림 ]
//
// Works for any airframe. 추진 계통 appears only when the aircraft reports
// rotor/engine data (tandem helicopter, engine aircraft) or per-motor ESC data
// (multicopter); the other panels share the freed width.
RowLayout {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _seen:       _t ? _t.seenKeys : ({})
    readonly property real _fw:         ScreenTools.defaultFontPixelWidth
    readonly property real _fh:         ScreenTools.defaultFontPixelHeight
    readonly property real _tileGap:    _fw * 0.6

    function anySeen(keys) {
        for (var i = 0; i < keys.length; i++) {
            if (_seen[keys[i]] === true) return true
        }
        return false
    }
    function fv(fact) {
        if (!fact) return NaN
        var v = fact.rawValue
        return (v === undefined) ? NaN : v
    }

    readonly property bool _rotorSeen:  anySeen([ "rot.front", "rot.rear" ])
    readonly property bool _tandem:     _seen["rot.rear"] === true      // second rotor reported → tandem; otherwise single main rotor
    readonly property bool _engineSeen: anySeen([ "eng.rpm", "coolant", "eng.cht", "eng.egt", "oil.temp", "oil.press", "eng.thr", "eng.fuelPress", "gb.front", "gb.rear" ])
    readonly property bool _fuelSeen:   anySeen([ "fuel.pct", "fuel.L", "eng.flow", "fuel.endurance", "pwr.aux", "pwr.genA" ])
    readonly property bool _motorsSeen: !!vehicle && !!vehicle.escs && vehicle.escs.count > 0
    readonly property bool _propulsion: !!vehicle && (_rotorSeen || _engineSeen || _motorsSeen)
    readonly property real _ecuHealth:  { var v = _t ? _t.values["eng.health"] : undefined; return v === undefined ? NaN : v }
    readonly property bool _armed:      !!vehicle && vehicle.armed
    readonly property bool _commLost:   !!vehicle && vehicle.vehicleLinkManager.communicationLost

    spacing: _fw * 0.6

    // ---- 비행 계기 ---------------------------------------------------------
    MLPanel {
        id:                     pfdPanel
        Layout.fillHeight:      true
        Layout.preferredWidth:  Math.round(Math.max(root._fw * 30, root.height + root._fh * 2.4))
        title:                  root.vehicle ? MLTheme.vehicleTypeName(root.vehicle) + (QGroundControl.multiVehicleManager.vehicles.count > 1 ? "  #" + root.vehicle.id : "")
                                             : qsTr("기체 없음")
        tag:                    "FLIGHT"
        detail:                 root.vehicle ? root.vehicle.flightMode : ""
        detailColor:            MLTheme.accent

        headerExtra: [
            Rectangle {
                visible:        !!root.vehicle
                width:          armText.implicitWidth + root._fw * 1.4
                height:         armText.implicitHeight + root._fh * 0.15
                radius:         height / 2
                color:          root._commLost || root._armed ? "#3a1416" : "#12301f"
                border.width:   1
                border.color:   root._commLost || root._armed ? MLTheme.warning : MLTheme.ok
                QGCLabel {
                    id:                 armText
                    anchors.centerIn:   parent
                    text:               root._commLost ? qsTr("통신 두절") : (root._armed ? qsTr("시동 ON") : qsTr("시동 OFF"))
                    color:              root._commLost || root._armed ? MLTheme.warning : MLTheme.ok
                    font.pointSize:     ScreenTools.smallFontPointSize
                    font.bold:          true
                }
            }
        ]

        MLPfd {
            anchors.fill:   parent
            vehicle:        root.vehicle
        }
    }

    // ---- 추진 계통 ---------------------------------------------------------
    MLPanel {
        id:                         propPanel
        visible:                    root._propulsion
        Layout.fillHeight:          true
        Layout.fillWidth:           true
        Layout.minimumWidth:        root._fw * 30
        Layout.preferredWidth:      root._fw * 56
        Layout.horizontalStretchFactor: 7
        title:                      qsTr("추진 계통")
        tag:                        "PROPULSION"
        detail: {
            if (!isNaN(root._ecuHealth)) return root._ecuHealth > 0 ? qsTr("ECU 정상") : qsTr("ECU 이상")
            if (root._t && root._t.provisionalLimits && (root._engineSeen || root._rotorSeen)) return qsTr("임계값 임시")
            return root._motorsSeen ? qsTr("모터 %1개").arg(root.vehicle.escs.count) : ""
        }
        detailColor:                isNaN(root._ecuHealth) ? MLTheme.dim : (root._ecuHealth > 0 ? MLTheme.ok : MLTheme.warning)

        readonly property real _split:      { var v = root._t ? root._t.values["rot.split"] : undefined; return v === undefined ? NaN : v }
        readonly property int  _splitLevel: { var l = root._t ? root._t.levels["rot.split"] : undefined; return l === undefined ? 0 : l }
        readonly property real _front:      { var v = root._t ? root._t.values["rot.front"] : undefined; return v === undefined ? NaN : v }
        readonly property real _rear:       { var v = root._t ? root._t.values["rot.rear"] : undefined; return v === undefined ? NaN : v }
        readonly property bool _engRpmSeen: root._seen["eng.rpm"] === true
        readonly property int  _gaugeCount: (_engRpmSeen ? 1 : 0) + (root._rotorSeen ? (root._tandem ? 2 : 1) : 0)
        readonly property real _syncW:      root._tandem ? root._fw * 13 : 0
        readonly property real _gaugeSize:  _gaugeCount === 0 ? 0
                                            : Math.max(root._fh * 4, Math.min((width - padding * 2 - _syncW - root._fw * 1.2 * _gaugeCount) / _gaugeCount,
                                                                              (height - root._fh * 1.9) * 0.62))

        // Dials: engine RPM, front rotor, sync, rear rotor
        Row {
            id:                         dials
            visible:                    propPanel._gaugeCount > 0
            anchors.horizontalCenter:   parent.horizontalCenter
            anchors.top:                parent.top
            spacing:                    root._fw * 1.2

            MLArcGauge {
                visible:    propPanel._engRpmSeen
                key:        "eng.rpm"
                title:      qsTr("엔진")
                size:       propPanel._gaugeSize
            }
            MLArcGauge {
                visible:    root._rotorSeen
                key:        "rot.front"
                title:      root._tandem ? qsTr("전방 로터") : qsTr("메인 로터")
                size:       propPanel._gaugeSize
                level:      isNaN(value) ? 0 : (root._tandem ? Math.max(1, propPanel._splitLevel) : 1)
            }

            // Tandem synchronisation: signed RPM difference on a centre-zero scale
            Column {
                visible:                root._tandem
                width:                  propPanel._syncW
                anchors.verticalCenter: parent.verticalCenter
                spacing:                root._fh * 0.25

                readonly property real _delta: propPanel._front - propPanel._rear
                readonly property color _c: propPanel._splitLevel === 3 ? MLTheme.warning : (propPanel._splitLevel === 2 ? MLTheme.caution : MLTheme.ok)

                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:           "TANDEM  Δ"
                    color:          MLTheme.faint
                    font.pointSize: ScreenTools.smallFontPointSize
                    font.letterSpacing: 1
                }
                QGCLabel {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text:           isNaN(parent._delta) ? "—" : (parent._delta >= 0 ? "+" : "") + parent._delta.toFixed(0) + " rpm"
                    color:          MLTheme.text
                    font.family:    ScreenTools.fixedFontFamily
                    font.pointSize: ScreenTools.mediumFontPointSize
                    font.bold:      true
                }
                // centre-zero bar, full scale = 6 % of front rotor speed
                Item {
                    width:  parent.width
                    height: root._fh * 0.7
                    readonly property real _frac: isNaN(propPanel._split) ? 0 : Math.min(1, propPanel._split / 6) * ((propPanel._front - propPanel._rear) >= 0 ? 1 : -1)
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: Math.max(3, root._fh * 0.22); radius: height / 2; color: MLTheme.panelRaised }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x:      parent._frac >= 0 ? parent.width / 2 : parent.width / 2 * (1 + parent._frac)
                        width:  Math.abs(parent._frac) * parent.width / 2
                        height: Math.max(3, root._fh * 0.22)
                        color:  parent.parent._c
                    }
                    Rectangle { anchors.centerIn: parent; width: 2; height: parent.height; color: MLTheme.dim }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width:          syncText.implicitWidth + root._fw * 1.6
                    height:         syncText.implicitHeight + root._fh * 0.2
                    radius:         height / 2
                    color:          Qt.rgba(parent._c.r, parent._c.g, parent._c.b, 0.15)
                    border.width:   1
                    border.color:   parent._c
                    QGCLabel {
                        id:                 syncText
                        anchors.centerIn:   parent
                        text:               isNaN(propPanel._split) ? qsTr("대기") : (propPanel._splitLevel >= 3 ? qsTr("동기 이상") : (propPanel._splitLevel === 2 ? qsTr("동기 주의") : qsTr("동기 양호")))
                                            + (isNaN(propPanel._split) ? "" : "  " + propPanel._split.toFixed(1) + "%")
                        color:              parent.parent._c
                        font.pointSize:     ScreenTools.smallFontPointSize
                        font.bold:          true
                    }
                }
            }

            MLArcGauge {
                visible:    root._tandem
                key:        "rot.rear"
                title:      qsTr("후방 로터")
                size:       propPanel._gaugeSize
                level:      isNaN(value) ? 0 : Math.max(1, propPanel._splitLevel)
            }
        }

        // Other engine / drivetrain values
        Flickable {
            id:                 engineFlick
            anchors.left:       parent.left
            anchors.right:      parent.right
            anchors.top:        dials.visible ? dials.bottom : parent.top
            anchors.topMargin:  dials.visible ? root._fh * 0.5 : 0
            anchors.bottom:     parent.bottom
            contentHeight:      engineGrid.height
            clip:               true
            boundsBehavior:     Flickable.StopAtBounds

            Grid {
                id:         engineGrid
                width:      engineFlick.width
                columns:    Math.max(2, Math.floor((width + root._tileGap) / (root._fw * 12 + root._tileGap)))
                spacing:    root._tileGap

                readonly property real _w: (width - spacing * (columns - 1)) / columns

                MLKeyTile { width: engineGrid._w; key: "coolant" }
                MLKeyTile { width: engineGrid._w; key: "eng.cht" }
                MLKeyTile { width: engineGrid._w; key: "eng.egt" }
                MLKeyTile { width: engineGrid._w; key: "eng.thr" }
                MLKeyTile { width: engineGrid._w; key: "oil.temp" }
                MLKeyTile { width: engineGrid._w; key: "oil.press" }
                MLKeyTile { width: engineGrid._w; key: "eng.fuelPress" }
                MLKeyTile { width: engineGrid._w; key: "gb.front" }
                MLKeyTile { width: engineGrid._w; key: "gb.rear" }
            }
        }

        // Per-motor RPM (multicopter / VTOL with ESC telemetry)
        MLMotorView {
            visible:        root._motorsSeen && !root._rotorSeen && !root._engineSeen
            anchors.fill:   parent
            vehicle:        root.vehicle
        }
    }

    // ---- 전원 · 연료 -------------------------------------------------------
    MLPanel {
        Layout.fillHeight:          true
        Layout.fillWidth:           true
        Layout.minimumWidth:        root._fw * 28
        Layout.preferredWidth:      root._fw * 34
        Layout.horizontalStretchFactor: 3
        title:                      root._fuelSeen ? qsTr("전원 · 연료") : qsTr("전원")
        tag:                        root._fuelSeen ? "POWER · FUEL" : "POWER"

        Flickable {
            id:             powerFlick
            anchors.fill:   parent
            contentHeight:  powerColumn.implicitHeight
            clip:           true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id:         powerColumn
                width:      powerFlick.width
                spacing:    root._fh * 0.5

                MLBatteryView {
                    width:      parent.width
                    vehicle:    root.vehicle
                }

                Grid {
                    id:         fuelGrid
                    visible:    root._fuelSeen
                    width:      parent.width
                    columns:    2
                    spacing:    root._tileGap

                    readonly property real _w: (width - spacing) / 2

                    MLKeyTile { width: fuelGrid._w; key: "fuel.pct" }
                    MLKeyTile { width: fuelGrid._w; key: "fuel.L" }
                    MLKeyTile { width: fuelGrid._w; key: "eng.flow" }
                    MLKeyTile { width: fuelGrid._w; key: "fuel.endurance" }
                    MLKeyTile { width: fuelGrid._w; key: "pwr.aux" }
                    MLKeyTile { width: fuelGrid._w; key: "pwr.genA" }
                }
            }
        }
    }

    // ---- 항법 · 통신 -------------------------------------------------------
    MLPanel {
        Layout.fillHeight:          true
        Layout.fillWidth:           true
        Layout.minimumWidth:        root._fw * 28
        Layout.preferredWidth:      root._fw * 34
        Layout.horizontalStretchFactor: 3
        title:                      qsTr("항법 · 통신")
        tag:                        "SYSTEM"
        detail:                     root.vehicle ? root.vehicle.firmwareTypeString : ""

        Flickable {
            id:             navFlick
            anchors.fill:   parent
            contentHeight:  navColumn.implicitHeight
            clip:           true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id:     navColumn
                width:  navFlick.width

                MLStatusRow {
                    width:  parent.width
                    label:  "GPS"
                    readonly property real _lock: root.vehicle ? root.fv(root.vehicle.gps.lock) : NaN
                    readonly property real _n:    root.vehicle ? root.fv(root.vehicle.gps.count) : NaN
                    value:  isNaN(_lock) ? "—" : (_lock >= 6 ? "RTK FIX" : (_lock === 5 ? "RTK FLOAT" : (_lock >= 3 ? "3D FIX" : (_lock === 2 ? "2D" : qsTr("없음"))))) + (isNaN(_n) ? "" : " (" + _n.toFixed(0) + ")")
                    level:  isNaN(_lock) ? 0 : (_lock >= 3 ? (_n < 8 ? 2 : 1) : 3)
                    bars:   isNaN(_n) ? 0 : Math.min(4, Math.floor(_n / 4))
                }
                MLStatusRow {
                    width:  parent.width
                    label:  "HDOP"
                    readonly property real _h: root.vehicle ? root.fv(root.vehicle.gps.hdop) : NaN
                    value:  isNaN(_h) ? "—" : _h.toFixed(1)
                    level:  isNaN(_h) ? 0 : (_h > 2.5 ? 2 : 1)
                }
                MLStatusRow {
                    width:  parent.width
                    label:  qsTr("텔레메트리")
                    readonly property real _rssi: root.vehicle ? root.fv(root.vehicle.radioStatus.lrssi) : NaN
                    readonly property bool _has:  !isNaN(_rssi) && _rssi !== 0
                    value:  !root.vehicle ? "—" : (root._commLost ? qsTr("두절") : (_has ? _rssi.toFixed(0) : qsTr("연결")))
                    unit:   root.vehicle && !root._commLost && _has ? "dBm" : ""
                    level:  !root.vehicle ? 0 : (root._commLost ? 3 : (_has && _rssi < -90 ? 2 : 1))
                    bars:   !root.vehicle || root._commLost ? 0 : (!_has ? 4 : Math.max(0, Math.min(4, Math.round((_rssi + 105) / 10))))
                }
                MLStatusRow {
                    width:  parent.width
                    label:  qsTr("조종기")
                    readonly property real _rc: root.vehicle ? root.fv(root.vehicle.rcRSSI) : NaN
                    readonly property bool _ok: !isNaN(_rc) && _rc >= 0 && _rc <= 100
                    value:  _ok ? _rc.toFixed(0) : "—"
                    unit:   _ok ? "%" : ""
                    level:  !_ok ? 0 : (_rc < 20 ? 3 : (_rc < 40 ? 2 : 1))
                    bars:   _ok ? Math.round(_rc / 25) : 0
                }
                MLStatusRow {
                    width:  parent.width
                    label:  qsTr("진동")
                    readonly property real _vib: root.vehicle ? Math.max(root.fv(root.vehicle.vibration.xAxis), root.fv(root.vehicle.vibration.yAxis), root.fv(root.vehicle.vibration.zAxis)) : NaN
                    value:  isNaN(_vib) ? "—" : (_vib > 60 ? qsTr("높음 ") : (_vib > 30 ? qsTr("주의 ") : qsTr("정상 "))) + _vib.toFixed(0)
                    unit:   isNaN(_vib) ? "" : "m/s²"
                    level:  isNaN(_vib) ? 0 : (_vib > 60 ? 3 : (_vib > 30 ? 2 : 1))
                }
                MLStatusRow {
                    width:  parent.width
                    label:  qsTr("홈 거리")
                    readonly property real _d: root.vehicle ? root.fv(root.vehicle.distanceToHome) : NaN
                    value:  isNaN(_d) ? "—" : (_d >= 1000 ? (_d / 1000).toFixed(2) : _d.toFixed(0))
                    unit:   isNaN(_d) ? "" : (_d >= 1000 ? "km" : "m")
                    level:  isNaN(_d) ? 0 : 1
                }
                MLStatusRow {
                    width:  parent.width
                    label:  qsTr("비행 시간 · 거리")
                    readonly property real _s: root.vehicle ? root.fv(root.vehicle.flightTime) : NaN
                    readonly property real _d: root.vehicle ? root.fv(root.vehicle.flightDistance) : NaN
                    value:  (isNaN(_s) ? "—" : Math.floor(_s / 60) + ":" + ("0" + Math.floor(_s % 60)).slice(-2))
                            + "  ·  " + (isNaN(_d) ? "—" : (_d >= 1000 ? (_d / 1000).toFixed(2) + " km" : _d.toFixed(0) + " m"))
                    level:  isNaN(_s) && isNaN(_d) ? 0 : 1
                }
            }
        }
    }

    // ---- 경고 · 알림 -------------------------------------------------------
    MLAlertPanel {
        Layout.fillHeight:          true
        Layout.fillWidth:           true
        Layout.minimumWidth:        root._fw * 30
        Layout.preferredWidth:      root._fw * 40
        Layout.horizontalStretchFactor: 4
        vehicle:                    root.vehicle
    }
}
