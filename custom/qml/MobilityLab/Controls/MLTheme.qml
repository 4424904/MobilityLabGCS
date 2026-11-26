pragma Singleton

import QtQuick

import QGroundControl
import QGroundControl.Controls

// MobilityLab console look: graphite surfaces split by hairlines, warm white
// text, numbers in IBM Plex Mono. Colour carries meaning only:
//   accent  (cyan)    route, selection, things the operator controls
//   target  (magenta) commanded / target values, as on airliner displays
//   active  (green)   modes that are engaged
//   caution (amber) / warning (red)  abnormal only
QtObject {
    // ---- scale: 1 design px at the default font size --------------------
    readonly property real u:               ScreenTools.defaultFontPixelHeight / 16

    // ---- type -------------------------------------------------------------
    readonly property string sans:          "IBM Plex Sans KR"
    readonly property string mono:          "IBM Plex Mono"
    readonly property real   fsLabel:       11 * u
    readonly property real   fsSmall:       12 * u
    readonly property real   fsBody:        13 * u
    readonly property real   fsValue:       14 * u
    readonly property real   fsBig:         22 * u

    // ---- surfaces ---------------------------------------------------------
    readonly property color bg:             "#07090B"
    readonly property color panelSolid:     "#0A0D10"
    readonly property color panel:          "#F20A0D10"
    readonly property color panelHeader:    "#0D1115"
    readonly property color panelRaised:    "#11161B"
    readonly property color tile:           "#0D1115"
    readonly property color line:           "#1B2026"
    readonly property color hair:           "#13181D"
    readonly property color lineStrong:     "#2A3038"

    // ---- text -------------------------------------------------------------
    readonly property color text:           "#E6E4DE"
    readonly property color bright:         "#F2F1EE"
    readonly property color label:          "#AEB4BB"
    readonly property color dim:            "#7D848D"
    readonly property color faint:          "#4A535C"

    // ---- meaning ----------------------------------------------------------
    readonly property color accent:         "#5BC0EB"
    readonly property color target:         "#E46BD6"
    readonly property color active:         "#6FD08C"
    readonly property color ok:             "#6FD08C"
    readonly property color caution:        "#F0B232"
    readonly property color warning:        "#FF5A52"
    readonly property color brand:          "#D80E18"
    readonly property real  radius:         6 * u

    // ---- floating panels over the map ---------------------------------------
    readonly property color glass:          "#EB0A0D10"
    readonly property color glassStrong:    "#F5090C0F"
    readonly property color glassEdge:      "#242B33"
    readonly property color glassEdgeHi:    "#33404B"
    readonly property real  panelRadius:    10 * u

    // ---- vehicle identity colours (map, lanes, event log) -------------------
    readonly property var vehiclePalette: ["#5BC0EB", "#C39BFF", "#B9DE6A", "#FF8FB1", "#7FD8D0", "#F2C46D"]
    function vehicleColor(id) {
        var i = Math.max(0, Number(id) - 1) % vehiclePalette.length
        return vehiclePalette[i]
    }

    readonly property color zoneNormal:     "#1F3B2A"
    readonly property color zoneCaution:    "#5A4416"
    readonly property color zoneWarning:    "#B23A33"

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
        if (level === 1) return label
        return faint
    }
    function zoneColor(name) {
        if (name === "warning") return zoneWarning
        if (name === "caution") return zoneCaution
        return zoneNormal
    }

    function vehicleTypeName(vehicle) {
        if (!vehicle) return ""
        var t = String(vehicle.vehicleTypeString).toLowerCase()
        if (t.indexOf("coaxial") >= 0)      return qsTr("동축 헬기")
        if (t.indexOf("helicopter") >= 0)   return qsTr("헬기")
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
        if (value === undefined || isNaN(value)) return "—"
        return Number(value).toLocaleString(Qt.locale("en_US"), "f", decimals === undefined ? 0 : decimals)
    }
    function pad2(n) { return ("0" + Math.floor(n)).slice(-2) }
    function duration(seconds) {
        if (isNaN(seconds) || seconds < 0) return "—"
        var h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = Math.floor(seconds % 60)
        return (h > 0 ? h + ":" + pad2(m) : m) + ":" + pad2(s)
    }
    function distance(m) {
        if (isNaN(m) || m < 0) return { v: "—", u: "" }
        return m >= 1000 ? { v: (m / 1000).toFixed(2), u: "km" } : { v: m.toFixed(0), u: "m" }
    }

    // ---- firmware ------------------------------------------------------------
    // Versions the console's commands were verified against in SITL. Older
    // versions usually work but are flagged so the operator checks first.
    readonly property var fwRecommended: ({ px4: [1, 16, 0], apm: [4, 5, 0] })
    function fwInfo(vehicle) {
        var r = { name: "—", version: "", known: false, ok: true, recommend: "", modeUnknown: false }
        if (!vehicle) return r
        var maj = vehicle.firmwareMajorVersion, min = vehicle.firmwareMinorVersion, pat = vehicle.firmwarePatchVersion
        r.name = vehicle.px4Firmware ? "PX4" : (vehicle.apmFirmware ? "ArduPilot" : String(vehicle.firmwareTypeString))
        r.known = maj !== undefined && maj >= 0
        if (r.known) r.version = maj + "." + Math.max(0, min) + "." + Math.max(0, pat)
        var rec = vehicle.px4Firmware ? fwRecommended.px4 : (vehicle.apmFirmware ? fwRecommended.apm : null)
        if (rec) {
            r.recommend = rec[0] + "." + rec[1]
            if (r.known) {
                var cur = [maj, Math.max(0, min), Math.max(0, pat)]
                for (var i = 0; i < 3; i++) { if (cur[i] !== rec[i]) { r.ok = cur[i] > rec[i]; break } }
            }
        }
        r.modeUnknown = (vehicle.px4Firmware || vehicle.apmFirmware) && /custom:|unknown/i.test(String(vehicle.flightMode))
        return r
    }
}
