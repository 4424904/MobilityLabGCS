pragma Singleton

import QtQuick
import QtCore

import QGroundControl
import QGroundControl.Controls

// MOBILITY LAB design system (v1.1)
//
//  Two themes, chosen in Settings or from the top bar:
//    night  graphite surfaces, for the operations room and dusk/night flying
//    day    light surfaces with near-black text, for sunlight on the flight line
//  The QGC palette (MLPlugin::paletteOverride) follows the same values, so QGC's own
//  pages (plan, setup, settings) switch with the console.
//
//  Colour carries meaning only:
//    brand   (MOBILITY LAB red)  identity: logo, the active page, focus marks — never a status
//    accent  (cyan / blue)       route, selection, things the operator controls
//    target  (magenta)           commanded / target values, as on airliner displays
//    active  (green)             modes that are engaged, normal
//    caution (amber) / warning (red-orange, filled + icon + text)   abnormal only
//  Text contrast is ≥ 7:1 for values and ≥ 4.5:1 for labels in both themes.
QtObject {
    id: t

    // ---- theme ----------------------------------------------------------------
    readonly property var  _indoor: QGroundControl.settingsManager.appSettings.indoorPalette
    // contrast: high-contrast day palette for direct sunlight on the flight line (v1.1) — pure
    // black text, strong rules, opaque panels; always light
    property bool contrast: false
    property Settings _display: Settings { category: "MLDisplay"; property alias contrast: t.contrast }
    readonly property bool day:     contrast || (_indoor ? !_indoor.rawValue : false)
    function setDay(on) { if (_indoor) _indoor.rawValue = !on; if (!on) contrast = false }
    function setContrast(on) { contrast = on }
    function pick(night, dayValue) { return day ? dayValue : night }
    function hc(normal, high) { return contrast ? high : normal }

    // ---- scale: 1 design px at the default font size ----------------------------
    // ScreenTools follows Settings › 화면 배율 (uiScalePercent) and the OS DPI.
    readonly property real u:               ScreenTools.defaultFontPixelHeight / 16

    // spacing scale (4-pt grid)
    readonly property real s1:  4 * u
    readonly property real s2:  8 * u
    readonly property real s3:  12 * u
    readonly property real s4:  16 * u
    readonly property real s5:  24 * u
    readonly property real s6:  32 * u

    // ---- type -------------------------------------------------------------------
    readonly property string sans:          "IBM Plex Sans KR"
    readonly property string mono:          "IBM Plex Mono"
    readonly property real   fsLabel:       12.5 * u     // captions, units, table heads
    readonly property real   fsSmall:       13.5 * u     // secondary text
    readonly property real   fsBody:        15 * u       // body, buttons
    readonly property real   fsValue:       17 * u       // numeric readouts
    readonly property real   fsTitle:       19 * u       // panel / page titles
    readonly property real   fsBig:         26 * u       // primary readouts
    readonly property real   fsHuge:        36 * u       // HUD primary values

    // ---- motion -----------------------------------------------------------------
    // performance mode "경량" (lite): no transitions at all
    readonly property bool lite:      MLState.gfxQuality === "lite" || MLState.gfxQuality === "low"
    readonly property int animFast:   lite ? 0 : 120
    readonly property int anim:       lite ? 0 : 200
    readonly property int animSlow:   lite ? 0 : 320
    readonly property int easing:     Easing.OutCubic

    // ---- surfaces -----------------------------------------------------------------
    readonly property color bg:             hc(pick("#07090C", "#E9ECEF"), "#FFFFFF")
    readonly property color panelSolid:     pick("#0C1014", "#FFFFFF")
    readonly property color panel:          hc(pick("#F20C1014", "#F7FFFFFF"), "#FFFFFF")
    readonly property color panelHeader:    pick("#10151A", "#F3F5F7")
    readonly property color panelRaised:    pick("#141A20", "#F0F2F5")
    readonly property color tile:           hc(pick("#10151A", "#F3F5F7"), "#F2F2F2")
    readonly property color hover:          pick("#1A2129", "#E4E8EC")
    readonly property color pressed:        pick("#222B34", "#D6DCE2")
    readonly property color line:           hc(pick("#222931", "#D3D9DF"), "#6B7680")
    readonly property color hair:           pick("#171D23", "#E3E7EB")
    readonly property color lineStrong:     hc(pick("#36404A", "#AAB4BE"), "#1F262C")
    readonly property color shadow:         pick("#99000000", "#33000000")
    readonly property color scrim:          pick("#B3050709", "#80202830")

    // ---- text ---------------------------------------------------------------------
    readonly property color text:           hc(pick("#ECEBE7", "#14181C"), "#000000")
    readonly property color bright:         pick("#FFFFFF", "#000000")
    readonly property color label:          hc(pick("#C2C8CF", "#3A434C"), "#111417")
    readonly property color dim:            hc(pick("#9AA3AD", "#56616C"), "#2A3036")
    readonly property color faint:          hc(pick("#66707A", "#8A949E"), "#4A535B")
    readonly property color onAccent:       pick("#04121A", "#FFFFFF")

    // ---- meaning ----------------------------------------------------------------------
    readonly property color accent:         hc(pick("#5CC4F0", "#0067A8"), "#004F82")
    readonly property color accentSoft:     pick("#1A5CC4F0", "#1A0067A8")
    readonly property color target:         pick("#EA72DC", "#A3168F")
    readonly property color active:         hc(pick("#6FD394", "#0B7A3B"), "#00612C")
    readonly property color ok:             active
    readonly property color caution:        hc(pick("#F5B83A", "#9A5B00"), "#7A4600")
    readonly property color cautionFill:    pick("#2E2208", "#FFF1D1")
    readonly property color warning:        hc(pick("#FF5F55", "#C8141C"), "#A80008")
    readonly property color warningFill:    pick("#3A0F0E", "#FFE1DF")
    readonly property color info:           pick("#8FB8FF", "#2D54A8")
    readonly property color demo:           pick("#C7A2FF", "#6A35B8")     // demo-mode marks
    readonly property color brand:          "#D80E18"
    readonly property color brandDeep:      "#9E0A12"
    readonly property real  radius:         6 * u

    // ---- floating panels over the map ----------------------------------------------------
    readonly property color glass:          hc(pick("#EE0C1014", "#F5FFFFFF"), "#FFFFFF")
    readonly property color glassStrong:    hc(pick("#F70B0F13", "#FBFFFFFF"), "#FFFFFF")
    readonly property color glassEdge:      hc(pick("#2A323B", "#C9D1D9"), "#1F262C")
    readonly property color glassEdgeHi:    pick("#3E4B57", "#9FAAB5")
    readonly property real  panelRadius:    10 * u

    // ---- vehicle identity colours (map, cards, event log) — distinct from status colours ----
    readonly property var vehiclePalette: day
        ? ["#0072B2", "#7B3FBF", "#2E7D32", "#C2185B", "#00838F", "#8D6E00"]
        : ["#5CC4F0", "#C39BFF", "#B9DE6A", "#FF8FB1", "#7FD8D0", "#F2C46D"]
    function vehicleColor(id) {
        var i = Math.max(0, Number(id) - 1) % vehiclePalette.length
        return vehiclePalette[i]
    }

    readonly property color zoneNormal:     pick("#1F3B2A", "#CDEBD8")
    readonly property color zoneCaution:    pick("#5A4416", "#FFE2A8")
    readonly property color zoneWarning:    pick("#B23A33", "#F6B3AE")

    // ACACT risk level (AcactCore PairEval.level): 0 normal · 1 conflict predicted (CPA) · 2 emergency
    function riskColor(level) {
        if (level >= 2) return warning
        if (level === 1) return caution
        return active
    }
    function riskName(level) {
        if (level >= 2) return qsTr("비상")
        if (level === 1) return qsTr("충돌 예측")
        return qsTr("정상")
    }

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
    function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

    function vehicleTypeName(vehicle) {
        if (!vehicle) return ""
        var tt = String(vehicle.vehicleTypeString).toLowerCase()
        if (tt.indexOf("coaxial") >= 0)      return qsTr("동축 헬기")
        if (tt.indexOf("helicopter") >= 0)   return qsTr("헬기")
        if (vehicle.vtol)                   return qsTr("VTOL")
        if (vehicle.fixedWing)              return qsTr("고정익")
        if (tt.indexOf("hexa") >= 0)         return qsTr("헥사콥터")
        if (tt.indexOf("octo") >= 0)         return qsTr("옥토콥터")
        if (vehicle.multiRotor)             return qsTr("멀티콥터")
        if (vehicle.rover)                  return qsTr("지상 차량")
        if (vehicle.sub)                    return qsTr("수중체")
        return qsTr("기체")
    }

    function formatValue(value, decimals) {
        if (value === undefined || value === null || isNaN(value)) return "—"
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
    function uavName(id) { return "UAV " + ("0" + id).slice(-2) }

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
