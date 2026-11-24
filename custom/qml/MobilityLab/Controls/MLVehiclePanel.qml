import QtQuick
import QtQuick.Layouts

import QGroundControl
import QGroundControl.Controls

// Right-hand column for any airframe:
//   1. Flight instrument (PFD) with vehicle name, mode and arm state
//   2. Vehicle status: battery, motors (if ESC data), navigation and link
//   3. Powertrain: rotors / engine / drivetrain / fuel, only when the aircraft
//      reports that data (tandem helicopter, engine aircraft)
// Each card collapses from its title row.
Item {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property var  _t:          typeof mlTandem !== "undefined" ? mlTandem : null
    readonly property var  _seen:       _t ? _t.seenKeys : ({})
    readonly property real _gap:        ScreenTools.defaultFontPixelHeight * 0.5

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
    readonly property bool _engineSeen: anySeen([ "eng.rpm", "coolant", "eng.cht", "eng.egt", "oil.temp", "oil.press", "eng.thr", "eng.fuelPress" ])
    readonly property bool _driveSeen:  anySeen([ "gb.front", "gb.rear" ])
    readonly property bool _fuelSeen:   anySeen([ "fuel.pct", "fuel.L", "eng.flow", "fuel.endurance" ])
    readonly property bool _auxSeen:    anySeen([ "pwr.aux", "pwr.genA" ])
    readonly property bool _powertrain: _rotorSeen || _engineSeen || _driveSeen || _fuelSeen || _auxSeen
    readonly property real _ecuHealth:  { var v = _t ? _t.values["eng.health"] : undefined; return v === undefined ? NaN : v }

    readonly property bool _armed:      !!vehicle && vehicle.armed
    readonly property bool _commLost:   !!vehicle && vehicle.vehicleLinkManager.communicationLost

    implicitWidth:  ScreenTools.defaultFontPixelWidth * 36
    implicitHeight: column.implicitHeight

    QGCFlickable {
        id:             flick
        anchors.fill:   parent
        contentHeight:  column.implicitHeight
        clip:           true

        Column {
            id:         column
            width:      flick.width
            spacing:    root._gap

            // ---- 1. Flight instrument ------------------------------------
            MLCard {
                width:          parent.width
                title:          root.vehicle ? (MLTheme.vehicleTypeName(root.vehicle) + (QGroundControl.multiVehicleManager.vehicles.count > 1 ? "  #" + root.vehicle.id : ""))
                                             : qsTr("기체 없음")
                detail:         root.vehicle ? root.vehicle.flightMode : ""
                detailColor:    MLTheme.accent
                collapsible:    true

                headerExtra: [
                    Rectangle {
                        visible:        !!root.vehicle
                        width:          armText.implicitWidth + ScreenTools.defaultFontPixelWidth * 1.4
                        height:         armText.implicitHeight + ScreenTools.defaultFontPixelHeight * 0.25
                        radius:         height / 2
                        color:          root._commLost ? "#3a1416" : (root._armed ? "#3a1416" : "#12301f")
                        border.width:   1
                        border.color:   root._commLost ? MLTheme.warning : (root._armed ? MLTheme.warning : MLTheme.ok)
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
                    width:      parent.width
                    height:     Math.round(width * 0.62)
                    vehicle:    root.vehicle
                }
            }

            // ---- 2. Vehicle status ---------------------------------------
            MLCard {
                width:      parent.width
                visible:    !!root.vehicle
                title:      qsTr("기체 상태")
                detail:     root.vehicle ? root.vehicle.firmwareTypeString : ""

                Column {
                    width:      parent.width
                    spacing:    ScreenTools.defaultFontPixelHeight * 0.45

                    MLSectionHeader { width: parent.width; title: qsTr("배터리") }
                    MLBatteryView { width: parent.width; vehicle: root.vehicle }

                    MLSectionHeader {
                        width:      parent.width
                        title:      qsTr("모터")
                        detail:     motors.visible ? qsTr("%1개").arg(motors._count) : ""
                        visible:    motors.visible
                    }
                    MLMotorView { id: motors; width: parent.width; vehicle: root.vehicle }

                    MLSectionHeader { width: parent.width; title: qsTr("항법 · 통신") }
                    Grid {
                        width:      parent.width
                        columns:    3
                        spacing:    ScreenTools.defaultFontPixelWidth * 0.6

                        readonly property real _w: (width - spacing * 2) / 3

                        MLStatTile {
                            width:  parent._w
                            label:  "GPS"
                            readonly property var _lock: root.vehicle ? root.fv(root.vehicle.gps.lock) : NaN
                            value:  isNaN(_lock) ? "—" : (_lock >= 6 ? "RTK" : (_lock === 5 ? "RTK F" : (_lock >= 3 ? "3D" : (_lock === 2 ? "2D" : qsTr("없음")))))
                            level:  isNaN(_lock) ? 0 : (_lock >= 3 ? 1 : 3)
                        }
                        MLStatTile {
                            width:  parent._w
                            label:  qsTr("위성 · HDOP")
                            readonly property real _n: root.vehicle ? root.fv(root.vehicle.gps.count) : NaN
                            readonly property real _h: root.vehicle ? root.fv(root.vehicle.gps.hdop) : NaN
                            value:  (isNaN(_n) ? "—" : _n.toFixed(0)) + (isNaN(_h) ? "" : " · " + _h.toFixed(1))
                            level:  isNaN(_n) ? 0 : (_n < 6 ? 3 : (_n < 10 || _h > 2 ? 2 : 1))
                        }
                        MLStatTile {
                            width:  parent._w
                            label:  qsTr("진동")
                            readonly property real _vib: root.vehicle ? Math.max(root.fv(root.vehicle.vibration.xAxis), root.fv(root.vehicle.vibration.yAxis), root.fv(root.vehicle.vibration.zAxis)) : NaN
                            value:  isNaN(_vib) ? "—" : _vib.toFixed(0)
                            unit:   isNaN(_vib) ? "" : "m/s²"
                            level:  isNaN(_vib) ? 0 : (_vib > 60 ? 3 : (_vib > 30 ? 2 : 1))
                        }
                        MLStatTile {
                            width:  parent._w
                            label:  qsTr("텔레메트리")
                            readonly property real _rssi: root.vehicle ? root.fv(root.vehicle.radioStatus.lrssi) : NaN
                            value:  root._commLost ? qsTr("두절") : (isNaN(_rssi) || _rssi === 0 ? qsTr("연결") : _rssi.toFixed(0))
                            unit:   (!root._commLost && !isNaN(_rssi) && _rssi !== 0) ? "dBm" : ""
                            level:  root._commLost ? 3 : 1
                        }
                        MLStatTile {
                            width:  parent._w
                            label:  qsTr("조종기 RSSI")
                            readonly property real _rc: root.vehicle ? root.fv(root.vehicle.rcRSSI) : NaN
                            value:  (isNaN(_rc) || _rc > 100 || _rc < 0) ? "—" : _rc.toFixed(0)
                            unit:   (isNaN(_rc) || _rc > 100 || _rc < 0) ? "" : "%"
                            level:  (isNaN(_rc) || _rc > 100 || _rc < 0) ? 0 : (_rc < 20 ? 3 : (_rc < 40 ? 2 : 1))
                        }
                        MLStatTile {
                            width:  parent._w
                            label:  qsTr("홈 거리")
                            readonly property real _d: root.vehicle ? root.fv(root.vehicle.distanceToHome) : NaN
                            value:  isNaN(_d) ? "—" : (_d >= 1000 ? (_d / 1000).toFixed(2) : _d.toFixed(0))
                            unit:   isNaN(_d) ? "" : (_d >= 1000 ? "km" : "m")
                            level:  isNaN(_d) ? 0 : 1
                        }
                    }
                }
            }

            // ---- 3. Powertrain (shown only when reported) -----------------
            MLCard {
                width:          parent.width
                visible:        !!root.vehicle && root._powertrain
                title:          qsTr("동력 계통")
                detail:         root._t && root._t.provisionalLimits ? qsTr("임계값 임시") : ""

                Column {
                    width:      parent.width
                    spacing:    ScreenTools.defaultFontPixelHeight * 0.15

                    MLRotorSync { width: parent.width; visible: root._rotorSeen }

                    MLSectionHeader {
                        width:          parent.width
                        visible:        root._engineSeen
                        title:          qsTr("엔진 · ECU")
                        detail:         isNaN(root._ecuHealth) ? "" : (root._ecuHealth > 0 ? qsTr("ECU 정상") : qsTr("ECU 이상"))
                        detailColor:    isNaN(root._ecuHealth) ? MLTheme.dim : (root._ecuHealth > 0 ? MLTheme.ok : MLTheme.warning)
                    }
                    MLGaugeRow { width: parent.width; key: "eng.rpm" }
                    MLGaugeRow { width: parent.width; key: "coolant" }
                    MLGaugeRow { width: parent.width; key: "eng.cht" }
                    MLGaugeRow { width: parent.width; key: "eng.egt" }
                    MLGaugeRow { width: parent.width; key: "oil.temp" }
                    MLGaugeRow { width: parent.width; key: "oil.press" }
                    MLGaugeRow { width: parent.width; key: "eng.thr" }
                    MLGaugeRow { width: parent.width; key: "eng.fuelPress" }

                    MLSectionHeader { width: parent.width; visible: root._driveSeen; title: qsTr("동력전달") }
                    MLGaugeRow { width: parent.width; key: "gb.front" }
                    MLGaugeRow { width: parent.width; key: "gb.rear" }

                    MLSectionHeader { width: parent.width; visible: root._fuelSeen; title: qsTr("연료") }
                    MLGaugeRow { width: parent.width; key: "fuel.pct" }
                    MLGaugeRow { width: parent.width; key: "fuel.L" }
                    MLGaugeRow { width: parent.width; key: "eng.flow" }
                    MLGaugeRow { width: parent.width; key: "fuel.endurance" }

                    MLSectionHeader { width: parent.width; visible: root._auxSeen; title: qsTr("보조 전원") }
                    MLGaugeRow { width: parent.width; key: "pwr.aux" }
                    MLGaugeRow { width: parent.width; key: "pwr.genA" }
                }
            }
        }
    }
}
