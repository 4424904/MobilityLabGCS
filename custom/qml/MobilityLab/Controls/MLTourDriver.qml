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
        // ---- STANDARD, nothing connected ------------------------------------------------------------
        [function() { MLState.setUiMode("standard"); MLState.applyPreset("single"); MLState.onboardingOpen = true }, 3],
        [function() { shot("02_onboarding") }, 2],
        [function() { MLState.onboardingOpen = false }, 2],
        [function() { shot("03_standard_no_vehicle") }, 2],
        [function() { MLState.prefsOpen = true }, 2],
        [function() { shot("04_preferences") }, 2],
        [function() { MLState.prefsOpen = false; MLState.demoOpen = true }, 2],
        [function() { shot("05_demo_panel") }, 2],
        // ---- STANDARD, one vehicle ----------------------------------------------------------------
        [function() { MLState.demoOpen = false; mlDemo.start("single") }, 8],
        [function() { return vs.count >= 1 && vs.get(0).initialConnectComplete }, 3],
        [function() { shot("06_standard_single_ready") }, 2],
        [function() { MLState.preflightOpen = true; mlGuard.runPreflight() }, 3],
        [function() { shot("07_preflight_check") }, 2],
        [function() { MLState.preflightOpen = false; MLState.alertPanelOpen = true }, 2],
        [function() { shot("08_alert_center") }, 2],
        [function() { MLState.alertPanelOpen = false; vs.get(0).armed = true }, 2],
        [function() { vs.get(0).startMission() }, 35],
        [function() { shot("09_standard_single_flying") }, 2],
        [function() { MLTheme.setDay(true); MLTheme.setContrast(true) }, 3],
        [function() { shot("10_high_contrast") }, 2],
        [function() { MLTheme.setContrast(false); MLTheme.setDay(false); mainWindow.showPlanView() }, 5],
        [function() { shot("11_plan_view") }, 3],
        // ---- ADVANCED, one vehicle --------------------------------------------------------------
        [function() { mainWindow.showFlyView(); MLState.setUiMode("advanced"); MLState.applyPreset("single") }, 3],
        [function() { shot("12_advanced_single") }, 2],
        [function() { MLState.layoutMenuOpen = true }, 2],
        [function() { shot("13_advanced_layout_menu") }, 2],
        [function() { MLState.layoutMenuOpen = false; vs.get(0).flightMode = vs.get(0).rtlFlightMode }, 2],
        // ---- two vehicles: ACACT in STANDARD, then ADVANCED -------------------------------------------
        [function() { mlDemo.stop() }, 8],
        [function() { MLState.setUiMode("standard"); mlDemo.start("duo") }, 15],
        [function() { return vs.count >= 2 && vs.get(0).initialConnectComplete && vs.get(1).initialConnectComplete }, 2],
        [function() { shot("14_standard_multi_ground") }, 2],
        [function() { MLState.demoAutoRequested = true }, 5],
        [function() { return mlGuard.running && hasEvent(/일괄 시작/) }, 15],
        [function() { shot("15_standard_multi_flying") }, 2],
        [function() { return mlGuard.avoiding > 0 }, 0],
        [function() { shot("16_standard_avoidance") }, 1],
        [function() { MLState.acactDetailOpen = true }, 1],
        [function() { shot("17_standard_acact_details") }, 2],
        [function() { MLState.acactDetailOpen = false; MLState.setUiMode("advanced"); MLState.applyPreset("fleet"); MLState.acactTimelineOpen = true }, 2],
        [function() { shot("18_advanced_acact_timeline") }, 2],
        [function() { MLState.acact3dOpen = true }, 4],
        [function() { shot("19_acact_3d") }, 2],
        [function() { MLState.tourSet("cam3d", "follow") }, 3],
        [function() { shot("19b_acact_3d_follow") }, 2],
        [function() { MLState.tourSet("cam3d", "top") }, 3],
        [function() { shot("19c_acact_3d_top") }, 2],
        [function() { MLState.tourSet("cam3d", "overview") }, 1],
        [function() { MLState.acact3dOpen = false; MLState.guardConsoleOpen = true }, 2],
        [function() { shot("20_acact_console") }, 2],
        [function() { MLState.guardConsoleOpen = false; MLState.acactTimelineOpen = false }, 0],
        [function() { return hasEvent(/회피 완료/) }, 3],
        [function() { shot("21_advanced_back_to_mission") }, 2],
        // ---- SHOWCASE: live demo ----------------------------------------------------------------------
        [function() { MLState.setUiMode("showcase") }, 7],
        [function() { log("pairs " + mlGuard.pairs.length + " active " + mlGuard.active); shot("22_showcase_live") }, 2],
        [function() { MLState.leaveShowcase(); MLState.setUiMode("standard") }, 2],
        // ---- link loss in STANDARD ----------------------------------------------------------------
        [function() { mlDemo.setLinkCut(2, true) }, 8],
        [function() { shot("23_standard_link_loss") }, 2],
        [function() { MLState.alertPanelOpen = true }, 2],
        [function() { shot("24_link_loss_alerts") }, 2],
        [function() { MLState.tourSet("alertHistory", "1") }, 2],
        [function() { shot("24b_alert_history") }, 2],
        [function() { MLState.tourSet("alertHistory", "0") }, 1],
        [function() { MLState.alertPanelOpen = false; mlDemo.setLinkCut(2, false) }, 8],
        [function() { MLState.setUiMode("advanced"); MLState.leftDetached = true; MLState.rightDetached = true }, 4],
        [function() { log("detached"); shot("25_dual_monitor") }, 3],
        [function() { MLState.leftDetached = false; MLState.rightDetached = false }, 2],
        // ---- after landing: analysis, PDF, SHOWCASE replay, English --------------------------------------
        [function() { return allLanded() }, 5],
        [function() { mlGuard.stop() }, 3],
        [function() { MLState.acactTimelineOpen = true }, 2],
        [function() { shot("26_timeline_after_flight") }, 2],
        [function() { MLState.acactTimelineOpen = false; MLState.analysisOpen = true }, 3],
        [function() { mlAnalysis.refresh(); if (mlAnalysis.sessions.length > 0) mlAnalysis.load(mlAnalysis.sessions[0].stamp) }, 4],
        [function() { shot("27_analysis") }, 2],
        [function() { log("pdf " + mlAnalysis.exportPdf(mlAnalysis.defaultReportPath())) }, 3],
        [function() { MLState.analysisOpen = false; mlDemo.stop() }, 8],
        // ---- v1.2 flight records (the demo flight, under 데모) ------------------------------------
        [function() { MLState.recordsOpen = true }, 2],
        [function() { MLState.tourSet("recordsFilter", "demo") }, 2],
        [function() { if (mlRecords.records.length > 0) mlRecords.load(mlRecords.records[0].stamp); log("records " + mlRecords.records.length + " loaded " + mlRecords.loaded) }, 3],
        [function() { shot("27b_records_summary") }, 2],
        [function() { MLState.tourSet("recordsTab", "replay"); MLState.tourSet("recordsCursor", String(mlRecords.duration * 0.45)) }, 5],
        [function() { shot("27c_records_replay") }, 2],
        [function() { MLState.tourSet("recordsTab", "charts") }, 3],
        [function() { shot("27d_records_charts") }, 2],
        [function() { MLState.tourSet("recordsTab", "events") }, 2],
        [function() { shot("27e_records_events") }, 2],
        [function() { MLState.tourSet("recordsTab", "fields") }, 2],
        [function() { shot("27f_records_info") }, 2],
        [function() { log("recpdf " + mlRecords.exportPdf("")) }, 3],
        [function() { MLState.tourSet("recordsTab", "summary"); MLState.recordsOpen = false }, 2],
        [function() { MLState.showcaseSource = "replay"; MLState.setUiMode("showcase") }, 12],
        [function() { shot("28_showcase_replay") }, 2],
        [function() { MLState.leaveShowcase(); MLState.showcaseSource = ""; MLState.setUiMode("standard"); mlUi.language = "en" }, 3],
        [function() { shot("29_english_standard") }, 2],
        [function() { MLState.setUiMode("advanced"); MLState.rightTab = "acact" }, 2],
        [function() { shot("30_english_advanced") }, 2],
        [function() { mlUi.language = "ko"; MLState.setUiMode("standard") }, 2],
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
