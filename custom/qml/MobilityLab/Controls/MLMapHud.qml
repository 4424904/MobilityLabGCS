import QtQuick
import QtPositioning

import QGroundControl
import QGroundControl.Controls

// Position readout in the top-right corner of the map: lat/lon, MGRS,
// bearing / range from home and altitude above sea level.
Rectangle {
    id: root

    property var vehicle: QGroundControl.multiVehicleManager.activeVehicle

    readonly property real u:       MLTheme.u
    readonly property bool _has:    !!vehicle && vehicle.coordinate && vehicle.coordinate.isValid
    readonly property var  _c:      _has ? vehicle.coordinate : null
    readonly property var  _home:   !!vehicle && vehicle.homePosition && vehicle.homePosition.isValid ? vehicle.homePosition : null

    function _dms(deg, pos, neg) {
        if (isNaN(deg)) return "—"
        var h = deg >= 0 ? pos : neg
        deg = Math.abs(deg)
        var d = Math.floor(deg), mf = (deg - d) * 60, m = Math.floor(mf), s = (mf - m) * 60
        return d + "°" + ("0" + m).slice(-2) + "'" + (s < 10 ? "0" : "") + s.toFixed(1) + "\"" + h
    }
    function _fv(fact) { if (!fact) return NaN; var v = fact.rawValue; return (v === undefined || v === null) ? NaN : Number(v) }

    readonly property string _mgrs: !!vehicle && vehicle.gps && vehicle.gps.mgrs ? String(vehicle.gps.mgrs.rawValue || "") : ""
    readonly property real _brg:    _has && _home ? _home.azimuthTo(_c) : NaN
    readonly property real _rng:    _has && _home ? _home.distanceTo(_c) : NaN
    readonly property real _amsl:   !!vehicle ? _fv(vehicle.altitudeAMSL) : NaN

    width:          grid.implicitWidth + 24 * u
    height:         grid.implicitHeight + 16 * u
    color:          "#D90A0D10"
    border.color:   MLTheme.line
    radius:         3 * u
    visible:        !!vehicle

    Grid {
        id:             grid
        x:              12 * u
        y:              8 * u
        columns:        2
        columnSpacing:  10 * u
        rowSpacing:     3 * u

        component Key: Text { color: MLTheme.dim; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsLabel; font.letterSpacing: 0.8 * u }
        component Val: Text { color: MLTheme.text; font.family: MLTheme.mono; font.pixelSize: MLTheme.fsSmall }

        Key { text: "LAT" }
        Val { text: root._has ? root._dms(root._c.latitude, "N", "S") : "—" }
        Key { text: "LON" }
        Val { text: root._has ? root._dms(root._c.longitude, "E", "W") : "—" }
        Key { text: "MGRS"; visible: root._mgrs !== "" }
        Val { text: root._mgrs; visible: root._mgrs !== "" }
        Key { text: "HOME" }
        Val {
            text: isNaN(root._rng) ? "—" : ("00" + Math.round((root._brg + 360) % 360)).slice(-3) + "° / " + (root._rng >= 1000 ? (root._rng / 1000).toFixed(2) + " km" : root._rng.toFixed(0) + " m")
        }
        Key { text: "AMSL" }
        Val { text: isNaN(root._amsl) ? "—" : root._amsl.toFixed(1) + " m" }
    }
}
