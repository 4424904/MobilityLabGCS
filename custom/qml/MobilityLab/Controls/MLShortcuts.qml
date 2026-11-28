import QtQuick
import QtQuick.Window

import QGroundControl

// Keyboard shortcuts. Defaults below; the operator can rebind any of them in 환경 설정 › 단축키
// (stored in MLState.shortcutsJson). Flight commands (arm, takeoff, HOLD, RTL, land, emergency
// stop) deliberately have NO shortcut: they keep the two-press / hold confirmation of the
// command bar, so a stray key press can never move an aircraft.
Item {
    id: root
    // window: the main window (for F11 full screen)
    property var window: null

    readonly property var actions: [
        { id: "mode.standard",  name: qsTr("STANDARD 모드"),              def: "F1" },
        { id: "mode.advanced",  name: qsTr("ADVANCED 모드"),              def: "F2" },
        { id: "mode.showcase",  name: qsTr("SHOWCASE 모드"),              def: "F3" },
        { id: "view.full",      name: qsTr("전체 화면"),                  def: "F11" },
        { id: "panel.left",     name: qsTr("왼쪽 패널 접기·펴기"),        def: "Ctrl+[" },
        { id: "panel.right",    name: qsTr("오른쪽 패널 접기·펴기"),      def: "Ctrl+]" },
        { id: "map.fit",        name: qsTr("전체 기체 맞춤"),             def: "Ctrl+Shift+F" },
        { id: "map.center",     name: qsTr("명령 대상 기체로 이동"),      def: "Ctrl+Shift+C" },
        { id: "vehicle.next",   name: qsTr("다음 기체 선택 (명령 대상)"), def: "Ctrl+Tab" },
        { id: "open.alerts",    name: qsTr("경고 센터"),                  def: "Ctrl+Shift+A" },
        { id: "open.preflight", name: qsTr("비행 전 통합 점검"),          def: "Ctrl+Shift+P" },
        { id: "open.console",   name: qsTr("ACACT 콘솔"),                 def: "Ctrl+Shift+G" },
        { id: "open.timeline",  name: qsTr("ACACT 타임라인"),             def: "Ctrl+Shift+T" },
        { id: "open.3d",        name: qsTr("3D 상황도"),                  def: "Ctrl+Shift+3" },
        { id: "open.analysis",  name: qsTr("ACACT 분석"),                 def: "Ctrl+Shift+R" },
        { id: "open.records",   name: qsTr("비행 기록"),                  def: "Ctrl+Shift+L" },
        { id: "theme.toggle",   name: qsTr("주간 · 야간 테마"),           def: "Ctrl+Shift+D" },
        { id: "theme.contrast", name: qsTr("고대비 (직사광선)"),          def: "Ctrl+Shift+H" },
        { id: "open.prefs",     name: qsTr("환경 설정"),                  def: "Ctrl+," },
        { id: "open.help",      name: qsTr("시작 안내 · 도움말"),         def: "Shift+F1" },
        { id: "close.overlay",  name: qsTr("열린 창 닫기 · 시연 종료"),   def: "Esc" }
    ]

    function custom() { try { return MLState.shortcutsJson ? JSON.parse(MLState.shortcutsJson) : {} } catch (e) { return {} } }
    function seqFor(id) {
        var c = custom()
        if (c[id] !== undefined) return c[id]
        for (var i = 0; i < actions.length; i++) if (actions[i].id === id) return actions[i].def
        return ""
    }
    function bind(id, seq) { var c = custom(); c[id] = seq; MLState.shortcutsJson = JSON.stringify(c) }
    function resetAll() { MLState.shortcutsJson = "" }
    // the action whose sequence is already seq (for conflict warnings in the editor)
    function owner(seq, except) {
        for (var i = 0; i < actions.length; i++) if (actions[i].id !== except && seqFor(actions[i].id) === seq) return actions[i]
        return null
    }

    function run(id) {
        switch (id) {
        case "mode.standard":  MLState.setUiMode("standard"); break
        case "mode.advanced":  MLState.setUiMode("advanced"); break
        case "mode.showcase":  MLState.setUiMode("showcase"); break
        case "view.full":      if (window) window.visibility = (window.visibility === Window.FullScreen ? Window.Maximized : Window.FullScreen); break
        case "panel.left":     MLState.leftOpen = !MLState.leftOpen; break
        case "panel.right":    MLState.rightOpen = !MLState.rightOpen; break
        case "map.fit":        MLState.fitAllRequested(); break
        case "map.center": {
            var v = QGroundControl.multiVehicleManager.activeVehicle
            if (v) MLState.centerRequested(v.coordinate)
            break
        }
        case "vehicle.next": {
            var vs = QGroundControl.multiVehicleManager.vehicles, a = QGroundControl.multiVehicleManager.activeVehicle
            if (vs.count < 2) break
            var k = 0
            for (var i = 0; i < vs.count; i++) if (vs.get(i) === a) k = i
            QGroundControl.multiVehicleManager.activeVehicle = vs.get((k + 1) % vs.count)
            break
        }
        case "open.alerts":    MLState.alertPanelOpen = !MLState.alertPanelOpen; break
        case "open.preflight": MLState.preflightOpen = !MLState.preflightOpen; break
        case "open.console":   MLState.guardConsoleOpen = !MLState.guardConsoleOpen; break
        case "open.timeline":  MLState.acactTimelineOpen = !MLState.acactTimelineOpen; break
        case "open.3d":        MLState.acact3dOpen = !MLState.acact3dOpen; break
        case "open.analysis":  MLState.analysisOpen = !MLState.analysisOpen; break
        case "open.records":   MLState.recordsOpen = !MLState.recordsOpen; break
        case "theme.toggle":   MLTheme.setDay(!MLTheme.day); break
        case "theme.contrast": MLTheme.setContrast(!MLTheme.contrast); break
        case "open.prefs":     MLState.prefsOpen = !MLState.prefsOpen; break
        case "open.help":      MLState.onboardingOpen = !MLState.onboardingOpen; break
        case "close.overlay":
            if (MLState.prefsOpen) MLState.prefsOpen = false
            else if (MLState.recordsOpen) MLState.recordsOpen = false
            else if (MLState.onboardingOpen) MLState.onboardingOpen = false
            else if (MLState.preflightOpen) MLState.preflightOpen = false
            else if (MLState.analysisOpen) MLState.analysisOpen = false
            else if (MLState.isShowcase) MLState.leaveShowcase()
            break
        }
    }

    Repeater {
        model: root.actions
        Item {
            Shortcut {
                sequence: { MLState.shortcutsJson; return root.seqFor(modelData.id) }
                context: Qt.ApplicationShortcut
                enabled: sequence !== ""
                onActivated: root.run(modelData.id)
            }
        }
    }
}
