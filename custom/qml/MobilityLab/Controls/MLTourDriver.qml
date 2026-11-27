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
    function next() {
        var s = step
        step++
        switch (s) {
        case 0:  wait = 2; break                                                   // start screen visible
        case 1:  shot("01_start_screen"); wait = 5; break
        case 2:  MLState.applyPreset("single"); wait = 2; break
        case 3:  shot("02_main_no_vehicle"); MLState.leftTab = "fleet"; wait = 2; break
        case 4:  shot("03_waiting_for_vehicles"); MLState.demoOpen = true; wait = 2; break
        case 5:  shot("04_demo_panel"); MLState.demoOpen = false; mlDemo.start("single"); wait = 20; break
        case 6:  if (vs.count < 1 || !vs.get(0).initialConnectComplete) { step--; break } MLState.leftTab = "flight"; wait = 3; break
        case 7:  shot("05_single_vehicle_ground"); MLState.preflightOpen = true; mlGuard.runPreflight(); wait = 3; break
        case 8:  shot("06_preflight_check"); MLState.preflightOpen = false; MLState.alertPanelOpen = true; wait = 2; break
        case 9:  shot("07_alert_center"); MLState.alertPanelOpen = false; vs.get(0).armed = true; wait = 2; break
        case 10: vs.get(0).startMission(); wait = 35; break
        case 11: shot("08_single_vehicle_mission"); MLState.leftOpen = false; wait = 3; break
        case 12: shot("09_map_layout_hud"); MLState.applyPreset("single"); MLState.layoutMenuOpen = true; wait = 2; break
        case 13: shot("10_layout_menu"); MLState.layoutMenuOpen = false; mainWindow.showPlanView(); wait = 5; break
        case 14: shot("11_plan_view"); mainWindow.showFlyView(); MLTheme.setDay(true); wait = 3; break
        case 15: shot("12_day_theme"); MLTheme.setDay(false); vs.get(0).flightMode = vs.get(0).rtlFlightMode; wait = 2; break
        // ---- two vehicles: ACACT -------------------------------------------------------------
        case 16: mlDemo.stop(); wait = 8; break
        case 17: mlDemo.start("duo"); MLState.applyPreset("fleet"); wait = 25; break
        case 18: if (vs.count < 2) { step--; break } shot("13_multi_vehicle_ground"); mlDemoAutoRun(); wait = 5; break
        case 19: if (!mlGuard.running || !hasEvent(/일괄 시작/)) { step--; break } wait = 15; break
        case 20: shot("14_multi_vehicle_flying"); wait = 0; break
        case 21: if (!(mlGuard.worstLevel >= 1 || mlGuard.avoiding > 0)) { step--; break } shot("15_acact_conflict_predicted"); wait = 1; break
        case 22: if (mlGuard.avoiding < 1) { step--; break } wait = 2; break
        case 23: shot("16_acact_avoidance"); MLState.acactTimelineOpen = true; wait = 2; break
        case 24: shot("17_acact_timeline"); MLState.acact3dOpen = true; wait = 4; break
        case 25: shot("18_acact_3d"); MLState.acact3dOpen = false; MLState.guardConsoleOpen = true; wait = 2; break
        case 26: shot("19_acact_console"); MLState.guardConsoleOpen = false; wait = 0; break
        case 27: if (!hasEvent(/회피 완료/)) { step--; break } wait = 4; break
        case 28: shot("20_back_to_mission"); mlDemo.setLinkCut(2, true); wait = 8; break
        case 29: shot("21_link_loss"); MLState.alertPanelOpen = true; wait = 2; break
        case 30: shot("22_link_loss_alerts"); MLState.alertPanelOpen = false; mlDemo.setLinkCut(2, false); wait = 8; break
        case 31: shot("23_link_restored"); MLState.leftDetached = true; MLState.rightDetached = true; wait = 4; break
        case 32: log("detached"); shot("24_dual_monitor"); wait = 2; break
        case 33: MLState.leftDetached = false; MLState.rightDetached = false; wait = 2; break
        // ---- after landing: analysis, PDF -----------------------------------------------------
        case 34: if (!allLanded()) { step--; break } wait = 5; break
        case 35: mlGuard.stop(); wait = 3; break
        case 36: MLState.analysisOpen = true; wait = 3; break
        case 37: mlAnalysis.refresh(); if (mlAnalysis.sessions.length > 0) mlAnalysis.load(mlAnalysis.sessions[0].stamp); wait = 4; break
        case 38: shot("25_analysis"); log("pdf " + mlAnalysis.exportPdf(mlAnalysis.defaultReportPath())); wait = 3; break
        case 39: MLState.analysisOpen = false; mlUi.language = "en"; wait = 4; break
        case 40: shot("26_english"); MLState.rightTab = "acact"; wait = 2; break
        case 41: shot("27_english_acact"); mlUi.language = "ko"; wait = 3; break
        case 42: log("done"); running = false; break
        }
    }
    property bool running: true
    // the demo panel's automatic demonstration (same operator workflow)
    function mlDemoAutoRun() { MLState.demoAutoRequested = true }
}
