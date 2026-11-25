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
        Layout.preferredWidth:  Math.round(Math.max(root._fw * 30, (root.height - root._fh * 3.6) / 0.56))
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
                    text:               root._commLost ? qsTr("통신 두절") : (root._armed ? qsTr("무장") : qsTr("안전"))
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

        readonly property bool _sideBySide: root._rotorSeen && root._engineSeen && width > root._fw * 50

        // Rotor synchronisation (tandem)
        MLRotorSync {
            id:             rotorSync
            visible:        root._rotorSeen
            anchors.left:   parent.left
            y:              propPanel._sideBySide ? Math.max(0, (parent.height - height) / 2) : 0
            width:          propPanel._sideBySide ? Math.max(parent.width * 0.42, discSize * 2 + root._fw * 12) : parent.width
            discSize:       Math.max(root._fh * 3.4, Math.min(root._fh * 5.2, (propPanel._sideBySide ? parent.height : parent.height * 0.5) - root._fh * 1.8))
        }

        // Engine / drivetrain tiles
        Flickable {
            id:                 engineFlick
            visible:            root._engineSeen
            anchors.left:       propPanel._sideBySide ? rotorSync.right : parent.left
            anchors.leftMargin: propPanel._sideBySide ? root._fw * 1.2 : 0
            anchors.right:      parent.right
            anchors.top:        propPanel._sideBySide || !root._rotorSeen ? parent.top : rotorSync.bottom
            anchors.topMargin:  propPanel._sideBySide || !root._rotorSeen ? 0 : root._fh * 0.4
            anchors.bottom:     parent.bottom
            contentHeight:      engineGrid.height
            clip:               true
            boundsBehavior:     Flickable.StopAtBounds

            Grid {
                id:         engineGrid
                width:      engineFlick.width
                columns:    Math.max(2, Math.floor((width + root._tileGap) / (root._fw * 13 + root._tileGap)))
                spacing:    root._tileGap

                readonly property real _w: (width - spacing * (columns - 1)) / columns

                MLKeyTile { width: engineGrid._w; key: "eng.rpm" }
                MLKeyTile { width: engineGrid._w; key: "eng.thr" }
                MLKeyTile { width: engineGrid._w; key: "coolant" }
                MLKeyTile { width: engineGrid._w; key: "eng.cht" }
                MLKeyTile { width: engineGrid._w; key: "eng.egt" }
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
        tag:                        "NAV · LINK"
        detail:                     root.vehicle ? root.vehicle.firmwareTypeString : ""

        Flickable {
            id:             navFlick
            anchors.fill:   parent
            contentHeight:  navGrid.height
            clip:           true
            boundsBehavior: Flickable.StopAtBounds

            Grid {
                id:         navGrid
                width:      navFlick.width
                columns:    width > root._fw * 33 ? 3 : 2
                spacing:    root._tileGap

                readonly property real _w: (width - spacing * (columns - 1)) / columns

                MLStatTile {
                    width:  navGrid._w
                    label:  "GPS"
                    readonly property real _lock: root.vehicle ? root.fv(root.vehicle.gps.lock) : NaN
                    value:  isNaN(_lock) ? "—" : (_lock >= 6 ? "RTK" : (_lock === 5 ? "RTK F" : (_lock >= 3 ? "3D" : (_lock === 2 ? "2D" : qsTr("없음")))))
                    level:  isNaN(_lock) ? 0 : (_lock >= 3 ? 1 : 3)
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("위성 · HDOP")
                    readonly property real _n: root.vehicle ? root.fv(root.vehicle.gps.count) : NaN
                    readonly property real _h: root.vehicle ? root.fv(root.vehicle.gps.hdop) : NaN
                    value:  (isNaN(_n) ? "—" : _n.toFixed(0)) + (isNaN(_h) ? "" : " · " + _h.toFixed(1))
                    level:  isNaN(_n) ? 0 : (_n < 6 ? 3 : (_n < 10 || _h > 2 ? 2 : 1))
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("텔레메트리")
                    readonly property real _rssi: root.vehicle ? root.fv(root.vehicle.radioStatus.lrssi) : NaN
                    value:  !root.vehicle ? "—" : (root._commLost ? qsTr("두절") : (isNaN(_rssi) || _rssi === 0 ? qsTr("연결") : _rssi.toFixed(0)))
                    unit:   (root.vehicle && !root._commLost && !isNaN(_rssi) && _rssi !== 0) ? "dBm" : ""
                    level:  !root.vehicle ? 0 : (root._commLost ? 3 : 1)
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("조종기 RSSI")
                    readonly property real _rc: root.vehicle ? root.fv(root.vehicle.rcRSSI) : NaN
                    value:  (isNaN(_rc) || _rc > 100 || _rc < 0) ? "—" : _rc.toFixed(0)
                    unit:   (isNaN(_rc) || _rc > 100 || _rc < 0) ? "" : "%"
                    level:  (isNaN(_rc) || _rc > 100 || _rc < 0) ? 0 : (_rc < 20 ? 3 : (_rc < 40 ? 2 : 1))
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("진동")
                    readonly property real _vib: root.vehicle ? Math.max(root.fv(root.vehicle.vibration.xAxis), root.fv(root.vehicle.vibration.yAxis), root.fv(root.vehicle.vibration.zAxis)) : NaN
                    value:  isNaN(_vib) ? "—" : _vib.toFixed(0)
                    unit:   isNaN(_vib) ? "" : "m/s²"
                    level:  isNaN(_vib) ? 0 : (_vib > 60 ? 3 : (_vib > 30 ? 2 : 1))
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("홈 거리")
                    readonly property real _d: root.vehicle ? root.fv(root.vehicle.distanceToHome) : NaN
                    value:  isNaN(_d) ? "—" : (_d >= 1000 ? (_d / 1000).toFixed(2) : _d.toFixed(0))
                    unit:   isNaN(_d) ? "" : (_d >= 1000 ? "km" : "m")
                    level:  isNaN(_d) ? 0 : 1
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("비행 시간")
                    readonly property real _s: root.vehicle ? root.fv(root.vehicle.flightTime) : NaN
                    value:  isNaN(_s) ? "—" : Math.floor(_s / 60) + ":" + ("0" + Math.floor(_s % 60)).slice(-2)
                    level:  isNaN(_s) ? 0 : 1
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("비행 거리")
                    readonly property real _d: root.vehicle ? root.fv(root.vehicle.flightDistance) : NaN
                    value:  isNaN(_d) ? "—" : (_d >= 1000 ? (_d / 1000).toFixed(2) : _d.toFixed(0))
                    unit:   isNaN(_d) ? "" : (_d >= 1000 ? "km" : "m")
                    level:  isNaN(_d) ? 0 : 1
                }
                MLStatTile {
                    width:  navGrid._w
                    label:  qsTr("GCS 거리")
                    readonly property real _d: root.vehicle ? root.fv(root.vehicle.distanceToGCS) : NaN
                    value:  isNaN(_d) || _d === 0 ? "—" : (_d >= 1000 ? (_d / 1000).toFixed(2) : _d.toFixed(0))
                    unit:   isNaN(_d) || _d === 0 ? "" : (_d >= 1000 ? "km" : "m")
                    level:  isNaN(_d) || _d === 0 ? 0 : 1
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
