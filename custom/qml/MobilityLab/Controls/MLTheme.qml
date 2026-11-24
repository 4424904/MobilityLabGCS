pragma Singleton

import QtQuick

import QGroundControl
import QGroundControl.Controls

// Shared colours and sizes for the MobilityLab console.
// The fly view is a single-screen console (dark navy panels around the map),
// kept the same in both QGC themes; status colours follow avionics conventions.
QtObject {
    readonly property color bg:             "#070b10"   // console background between panels
    readonly property color panel:          "#eb0e151c"
    readonly property color panelSolid:     "#0e151c"
    readonly property color panelHeader:    "#121b23"
    readonly property color panelRaised:    "#18232c"
    readonly property color line:           "#1f2d38"
    readonly property color lineStrong:     "#33475a"
    readonly property color text:           "#e8eeeb"
    readonly property color dim:            "#93a3a8"
    readonly property color label:          "#b9c6ca"   // value labels: readable over imagery
    readonly property color faint:          "#5f7076"
    readonly property color accent:         "#4fd3ea"   // selected / informational
    readonly property color active:         "#ef5fe0"   // active route, RTL
    readonly property color ok:             "#4ccf7c"
    readonly property color caution:        "#f5b331"
    readonly property color warning:        "#ff4f4f"
    readonly property color brand:          "#d80e18"
    readonly property color tile:           "#131d25"
    readonly property real  radius:         ScreenTools.defaultFontPixelWidth * 0.9

    readonly property color zoneNormal:     "#2c7a4c"
    readonly property color zoneCaution:    "#9c7320"
    readonly property color zoneWarning:    "#9c2c2c"

    // TandemTelemetry levels: 0 no data, 1 normal, 2 caution, 3 warning
    function levelColor(level) {
        if (level === 3) return warning
        if (level === 2) return caution
        if (level === 1) return text
        return faint
    }

    function levelAccent(level) {
        if (level === 3) return warning
        if (level === 2) return caution
        if (level === 1) return ok
        return faint
    }

    function zoneColor(name) {
        if (name === "warning") return zoneWarning
        if (name === "caution") return zoneCaution
        return zoneNormal
    }

    // Korean name for the connected airframe type
    function vehicleTypeName(vehicle) {
        if (!vehicle) return ""
        var t = String(vehicle.vehicleTypeString).toLowerCase()
        if (t.indexOf("coaxial") >= 0)      return qsTr("동축 헬리콥터")
        if (t.indexOf("helicopter") >= 0)   return qsTr("헬리콥터")
        if (vehicle.vtol)                   return qsTr("VTOL")
        if (vehicle.fixedWing)              return qsTr("고정익")
        if (t.indexOf("hexa") >= 0)         return qsTr("헥사콥터")
        if (t.indexOf("octo") >= 0)         return qsTr("옥토콥터")
        if (vehicle.multiRotor)             return qsTr("멀티콥터")
        if (vehicle.rover)                  return qsTr("지상 차량")
        if (vehicle.sub)                    return qsTr("수중체")
        return qsTr("기체")
    }

    function formatValue(value, decimals) {
        if (value === undefined || isNaN(value)) {
            return "—"
        }
        return Number(value).toLocaleString(Qt.locale("en_US"), "f", decimals === undefined ? 0 : decimals)
    }
}
