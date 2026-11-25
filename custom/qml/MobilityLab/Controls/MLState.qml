pragma Singleton

import QtQuick

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
