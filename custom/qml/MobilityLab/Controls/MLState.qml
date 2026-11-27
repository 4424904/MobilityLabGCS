pragma Singleton

import QtQuick
import QtCore

import QGroundControl

// Values the operator has commanded from the console (목표 조정), shown as
// magenta targets on the flight display. Cleared when the selected vehicle changes.
QtObject {
    id: root

    property real targetSpeed:      NaN
    property real targetAlt:        NaN     // relative to home, metres
    property real targetHeading:    NaN
    property bool setpointsOpen:    false
    property bool fleetOpen:        false
    property bool profileOpen:      false
    property bool guardConsoleOpen: false
    property bool analysisOpen:     false
    // second monitor: the ACACT console / analysis in their own windows
    property bool consoleDetached:  false
    property bool analysisDetached: false

    // ---- layout (saved per user, restored at start) ---------------------
    // preset: "single" 단일 기체 · "fleet" 다기체 · "map" 지도 중심 · "custom"
    property bool   leftOpen:       true
    property bool   rightOpen:      true
    property real   leftWidth:      400     // design px (× MLTheme.u)
    property real   rightWidth:     390
    property string leftTab:        "flight"    // flight · fleet
    property string rightTab:       "systems"   // systems · acact
    property bool   dockOpen:       true
    property string layoutPreset:   "single"
    property bool   showPositionHud: true
    property bool   showTrails:     true
    property bool   showPredictions: true
    property bool   alertCenterOpen: false
    property bool   preflightOpen:  false
    property bool   acactTimelineOpen: false
    property bool   acact3dOpen:    false
    property bool   bootDone:       false

    property Settings _layout: Settings {
        category:                   "MLLayout"
        property alias leftOpen:    root.leftOpen
        property alias rightOpen:   root.rightOpen
        property alias leftWidth:   root.leftWidth
        property alias rightWidth:  root.rightWidth
        property alias leftTab:     root.leftTab
        property alias rightTab:    root.rightTab
        property alias dockOpen:    root.dockOpen
        property alias layoutPreset: root.layoutPreset
        property alias showPositionHud: root.showPositionHud
        property alias showTrails:  root.showTrails
        property alias showPredictions: root.showPredictions
        property alias profileOpen: root.profileOpen
    }

    // map requests from panels (handled by the fly view map)
    signal fitAllRequested()
    signal centerRequested(var coordinate)
    signal measureRequested(string kind)        // "distance" · "area" · ""

    function applyPreset(p) {
        layoutPreset = p
        if (p === "single") { leftOpen = true; rightOpen = true; leftTab = "flight"; rightTab = "systems"; dockOpen = true }
        else if (p === "fleet") { leftOpen = true; rightOpen = true; leftTab = "fleet"; rightTab = "acact"; dockOpen = true }
        else if (p === "map") { leftOpen = false; rightOpen = false; dockOpen = true }
    }
    function markCustom() { if (layoutPreset !== "custom") layoutPreset = "custom" }

    // ACACT Guard ids (D1…D4) of the connected vehicles: MAVLink system id n → Dn
    function guardDrones() {
        var vs = QGroundControl.multiVehicleManager.vehicles
        var ids = []
        for (var i = 0; i < vs.count; i++) {
            var id = vs.get(i).id
            if (id >= 1 && id <= 4) ids.push("D" + id)
        }
        ids.sort()
        return ids.join(",")
    }

    // ---- event log (left column) ----------------------------------------
    // level: 0 info · 1 ok · 2 caution · 3 warning · 4 operator command
    property ListModel events: ListModel {}
    function log(text, level, vehicleId, source) {
        text = String(text).replace(/<[^>]*>/g, "").trim()
        if (text === "") return
        var d = new Date()
        events.insert(0, { t: Qt.formatTime(d, "hh:mm:ss"), text: text, level: level === undefined ? 0 : level,
                           vid: vehicleId === undefined ? 0 : vehicleId, src: source === undefined ? "" : source })
        if (events.count > 400) events.remove(400, events.count - 400)
    }
    function recentlyLogged(text, n) {
        text = String(text).replace(/<[^>]*>/g, "").trim()
        for (var i = 0; i < Math.min(n || 6, events.count); i++) if (events.get(i).text === text) return true
        return false
    }
    function command(text) {
        var v = _vehicle
        log(text, 4, v ? v.id : 0, "GCS")
    }

    readonly property var _vehicle: QGroundControl.multiVehicleManager.activeVehicle
    on_VehicleChanged: { targetSpeed = NaN; targetAlt = NaN; targetHeading = NaN }
}
