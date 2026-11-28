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
    property bool   showVehicleHud: false     // also shown whenever the instrument panel is folded
    property bool   showPredictions: true
    property bool   alertCenterOpen: false
    property bool   preflightOpen:  false
    property bool   demoOpen:       false
    property bool   demoAutoRequested: false   // start the automatic demonstration (demo panel / tour)
    property bool   alertPanelOpen: false
    property bool   layoutMenuOpen: false
    // side panels in their own windows (second monitor)
    property bool   leftDetached:   false
    property bool   rightDetached:  false
    property bool   acactTimelineOpen: false
    property bool   acact3dOpen:    false
    property bool   acact3dDetached: false
    property bool   bootDone:       false

    // ---- operating mode (v1.1) ----------------------------------------------
    // standard  기본 운용: map first, flight-critical information and readiness only, details on demand
    // advanced  전문 관제: every panel of v1.0 (QGC functions, ACACT console, telemetry, analysis)
    // showcase  기술 시연: full-window presentation of the built-in demo or of a recorded flight
    // Changing the mode only changes what the screen shows. It never touches a vehicle, a link,
    // a mission, the ACACT guard or any safety function (verified in SITL: tools/ci_sitl.sh "modes").
    property string uiMode:         "standard"
    property string _modeBeforeShowcase: "standard"
    property string showcaseSource: ""          // "demo" · "replay" — what the showcase screen presents
    property bool   onboardingDone: false
    property bool   onboardingOpen: false
    property bool   prefsOpen:      false
    property bool   recordsOpen:    false       // v1.2 flight records
    property bool   helpTips:       true        // hover help on buttons
    property string shortcutsJson:  ""          // operator's own key bindings (MLShortcuts)
    property bool   acactDetailOpen: false      // STANDARD: the ACACT details opened from the status strip
    property string gfxQuality:     "auto"      // v1.2 performance mode: auto · lite · balanced · high
    property bool   voiceAlerts:    true        // speak 위험 / 긴급 alerts (QGC voice output, its volume / mute)
    property int    voiceMinLevel:  3
    readonly property bool isStandard: uiMode === "standard"
    readonly property bool isAdvanced: uiMode === "advanced"
    readonly property bool isShowcase: uiMode === "showcase"
    signal modeRefused(string mode, string reason)

    // Real (non-demo) vehicles connected: SHOWCASE hides the flight controls, so it is only
    // available when nothing real is connected. Returns "" when allowed.
    function showcaseBlockReason() {
        var vs = QGroundControl.multiVehicleManager.vehicles
        var demo = typeof mlDemo !== "undefined" ? mlDemo : null
        var real = 0
        for (var i = 0; i < vs.count; i++) {
            var v = vs.get(i)
            if (!(demo && demo.active && demo.isDemoSysid(v.id))) real++
        }
        return real > 0 ? qsTr("실기체 %1대가 연결되어 있어 시연 모드로 바꿀 수 없습니다 — 비행 조작 화면을 숨기지 않기 위해서입니다").arg(real) : ""
    }
    function setUiMode(m) {
        if (m !== "standard" && m !== "advanced" && m !== "showcase") return false
        if (m === uiMode) return true
        if (m === "showcase") {
            var why = showcaseBlockReason()
            if (why !== "") { modeRefused(m, why); return false }
            _modeBeforeShowcase = uiMode
        }
        uiMode = m
        return true
    }
    function leaveShowcase() { if (uiMode === "showcase") uiMode = _modeBeforeShowcase === "showcase" ? "standard" : _modeBeforeShowcase }
    property var    alertCenter:    null      // MLAlertCenter (created by the fly view)

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
        property alias showVehicleHud: root.showVehicleHud
        property alias showPredictions: root.showPredictions
        property alias profileOpen: root.profileOpen
    }
    property Settings _prefs: Settings {
        category:                       "MLPrefs"
        property alias uiMode:          root._savedMode
        property alias onboardingDone:  root.onboardingDone
        property alias helpTips:        root.helpTips
        property alias shortcutsJson:   root.shortcutsJson
        property alias modeBeforeShowcase: root._modeBeforeShowcase
        property alias gfxQuality:      root.gfxQuality
        property alias voiceAlerts:     root.voiceAlerts
        property alias voiceMinLevel:   root.voiceMinLevel
    }
    // the saved mode: SHOWCASE is never restored at start (it needs the operator to pick a source)
    property string _savedMode: "standard"
    on_SavedModeChanged: if (!_modeRestored) { _modeRestored = true; uiMode = (_savedMode === "advanced") ? "advanced" : "standard" }
    property bool _modeRestored: false
    onUiModeChanged: { _modeRestored = true; if (uiMode !== "showcase") _savedMode = uiMode }

    // ---- ACACT timeline (filled by MLAcactRecorder from the guard's own events and evaluations) ----
    // kind: start · stop · predict · clear · takeover · release · lost · operator · info
    property ListModel acactEvents: ListModel {}
    property var  acactSep: []          // [{ t, d, level }] closest pair distance, 2 Hz
    property int  acactSepRev: 0         // bumps when acactSep grows (arrays are not observable)
    property real acactT0: -1            // guard time at the first sample of this run

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
