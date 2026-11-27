import QtQuick

import QGroundControl

// Screen-capture tour (only with ML_TOUR=1, used by tools/ui_tour.sh): walks through the console
// the way an operator would — demo start, automatic demonstration, every panel and view — and
// prints "MLTOUR shot <name>" when a screen is ready to capture. It only changes what is shown
// (panels, tabs, views, theme, language) and uses the same operator functions as the buttons.
Item {
    id: drv
    property int step: 0
    property int wait: 0
    readonly property var vs: QGroundControl.multiVehicleManager.vehicles

    function log(t) { console.log("MLTOUR " + t) }
    function shot(n) { log("shot " + n) }
    function hasEvent(re) {
        for (var i = 0; i < MLState.acactEvents.count; i++) if (re.test(MLState.acactEvents.get(i).text)) return true
        return false
    }
    function allLanded() {
        for (var i = 0; i < vs.count; i++) if (vs.get(i).flying || vs.get(i).armed) return false
        return vs.count > 0
    }

    Timer {
        interval: 1000; repeat: true; running: true
        onTriggered: {
            if (drv.wait > 0) { drv.wait--; return }
            drv.next()
        }
    }

    // each step: do something, then wait n seconds (or until a condition) before the next
    // the tour: [action, seconds to wait] — a "shot" step only announces the screen, so nothing
    // changes on screen while it is captured
    readonly property var plan: [
        [function() {}, 2],
        [function() { shot("01_start_screen") }, 5],
        [function() { MLState.applyPreset("single") }, 2],
        [function() { shot("02_main_no_vehicle") }, 2],
        [function() { MLState.leftTab = "fleet" }, 2],
        [function() { shot("03_waiting_for_vehicles") }, 2],
        [function() { MLState.demoOpen = true }, 2],
        [function() { shot("04_demo_panel") }, 2],
        [function() { MLState.demoOpen = false; mlDemo.start("single") }, 8],
        [function() { return vs.count >= 1 && vs.get(0).initialConnectComplete }, 0],
        [function() { MLState.leftTab = "flight" }, 3],
        [function() { shot("05_single_vehicle_ground") }, 2],
        [function() { MLState.preflightOpen = true; mlGuard.runPreflight() }, 3],
        [function() { shot("06_preflight_check") }, 2],
        [function() { MLState.preflightOpen = false; MLState.alertPanelOpen = true }, 2],
        [function() { shot("07_alert_center") }, 2],
        [function() { MLState.alertPanelOpen = false; vs.get(0).armed = true }, 2],
        [function() { vs.get(0).startMission() }, 35],
        [function() { shot("08_single_vehicle_mission") }, 2],
        [function() { MLState.leftOpen = false }, 3],
        [function() { shot("09_map_layout_hud") }, 2],
        [function() { MLState.applyPreset("single"); MLState.layoutMenuOpen = true }, 2],
        [function() { shot("10_layout_menu") }, 2],
        [function() { MLState.layoutMenuOpen = false; mainWindow.showPlanView() }, 5],
        [function() { shot("11_plan_view") }, 3],
        [function() { mainWindow.showFlyView(); MLTheme.setDay(true) }, 3],
        [function() { shot("12_day_theme") }, 2],
        [function() { MLTheme.setDay(false); vs.get(0).flightMode = vs.get(0).rtlFlightMode }, 2],
        // ---- two vehicles: ACACT ---------------------------------------------------------------
        [function() { mlDemo.stop() }, 8],
        [function() { mlDemo.start("duo"); MLState.applyPreset("fleet") }, 15],
        [function() { return vs.count >= 2 && vs.get(0).initialConnectComplete && vs.get(1).initialConnectComplete }, 2],
        [function() { shot("13_multi_vehicle_ground") }, 2],
        [function() { MLState.demoAutoRequested = true }, 5],
        [function() { return mlGuard.running && hasEvent(/일괄 시작/) }, 15],
        [function() { shot("14_multi_vehicle_flying") }, 2],
        [function() { return mlGuard.worstLevel >= 1 || mlGuard.avoiding > 0 }, 0],
        [function() { shot("15_acact_conflict_predicted") }, 2],
        [function() { return mlGuard.avoiding > 0 }, 1],
        [function() { shot("16_acact_avoidance") }, 2],
        [function() { MLState.acactTimelineOpen = true }, 2],
        [function() { shot("17_acact_timeline") }, 2],
        [function() { MLState.acact3dOpen = true }, 4],
        [function() { shot("18_acact_3d") }, 2],
        [function() { MLState.acact3dOpen = false; MLState.guardConsoleOpen = true }, 2],
        [function() { shot("19_acact_console") }, 2],
        [function() { MLState.guardConsoleOpen = false }, 0],
        [function() { return hasEvent(/회피 완료/) }, 4],
        [function() { shot("20_back_to_mission") }, 2],
        [function() { mlDemo.setLinkCut(2, true) }, 8],
        [function() { shot("21_link_loss") }, 2],
        [function() { MLState.alertPanelOpen = true }, 2],
        [function() { shot("22_link_loss_alerts") }, 2],
        [function() { MLState.alertPanelOpen = false; mlDemo.setLinkCut(2, false) }, 8],
        [function() { shot("23_link_restored") }, 2],
        [function() { MLState.leftDetached = true; MLState.rightDetached = true }, 4],
        [function() { log("detached"); shot("24_dual_monitor") }, 3],
        [function() { MLState.leftDetached = false; MLState.rightDetached = false }, 2],
        // ---- after landing: analysis, PDF, English ---------------------------------------------
        [function() { return allLanded() }, 5],
        [function() { mlGuard.stop() }, 3],
        [function() { MLState.acactTimelineOpen = true }, 2],
        [function() { shot("25_timeline_after_flight") }, 2],
        [function() { MLState.acactTimelineOpen = false; MLState.analysisOpen = true }, 3],
        [function() { mlAnalysis.refresh(); if (mlAnalysis.sessions.length > 0) mlAnalysis.load(mlAnalysis.sessions[0].stamp) }, 4],
        [function() { shot("26_analysis") }, 2],
        [function() { log("pdf " + mlAnalysis.exportPdf(mlAnalysis.defaultReportPath())) }, 3],
        [function() { MLState.analysisOpen = false; mlUi.language = "en" }, 2],
        [function() { log("key Return") }, 3],
        [function() { shot("27_english") }, 2],
        [function() { MLState.rightTab = "acact" }, 2],
        [function() { shot("28_english_acact") }, 2],
        [function() { mlUi.language = "ko" }, 2],
        [function() { log("key Return") }, 2],
        [function() { log("done") }, 0]
    ]
    function next() {
        if (step >= plan.length) return
        var r = plan[step][0]()
        if (r === false) return             // a condition: try again next second
        wait = plan[step][1]
        step++
    }
}
