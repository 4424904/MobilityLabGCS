// MobilityLab GCS: QGC v5.1.5 FlyView rearranged as a single-screen console.
//
//   ┌ top bar: menu · status · mode · UAV tabs · confirm · indicators · clock ─┐
//   │ 비행 계기 (FMA, PFD,  │ 지도 + QGC 지도 도구 + 목표 조정      │ 추진 · 추세 │
//   │ 핵심 수치, 링크)      │                                       │ 전원 · 경고 │
//   │ MLFlightColumn        ├ 고도 단면 (MLProfile) ────────────────┤ 미션        │
//   ├ 단계 · 명령 · 비상정지 (MLCommandBar) ─────────────────────────────────────┤
//
// The map, QGC's widget layer and the guided value slider live inside the map
// pane. Upstream behaviour (pip video, 3D view, guided actions) is unchanged.
// In full-screen video the console hides and the map pane fills the window.
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts

import QtLocation
import QtPositioning
import QtQuick.Window
import QtQml.Models

import QGroundControl
import QGroundControl.Controls
import QGroundControl.FlyView
import QGroundControl.FlightMap
import QGroundControl.Toolbar
import QGroundControl.Viewer3D

import MobilityLab.Controls

Item {
    id: _root

    readonly property bool _is3DMode:       QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D
    readonly property bool _keepSceneAlive: QGroundControl.settingsManager.viewer3DSettings.keepSceneAlive.rawValue

    // These should only be used by MainRootWindow
    property var planController:    _planController
    property var guidedController:  _guidedController

    PlanMasterController {
        id:                     _planController
        flyView:                true
        Component.onCompleted:  start()
    }

    property bool   _mainWindowIsMap:       mapControl.pipState.state === mapControl.pipState.fullState
    property bool   _isFullWindowItemDark:  _mainWindowIsMap ? mapControl.isSatelliteMap : true
    property var    _activeVehicle:         QGroundControl.multiVehicleManager.activeVehicle
    property var    _missionController:     _planController.missionController
    property var    _geoFenceController:    _planController.geoFenceController
    property var    _rallyPointController:  _planController.rallyPointController
    property real   _margins:               ScreenTools.defaultFontPixelWidth / 2
    property var    _guidedController:      guidedActionsController
    property var    _guidedValueSlider:     guidedValueSlider
    property var    _widgetLayer:           widgetLayer
    property real   _toolsMargin:           ScreenTools.defaultFontPixelWidth * 0.75
    property rect   _centerViewport:        Qt.rect(0, 0, width, height)
    property real   _rightPanelWidth:       ScreenTools.defaultFontPixelWidth * 30
    property var    _mapControl:            mapControl
    property real   _widgetMargin:          ScreenTools.defaultFontPixelWidth * 0.75

    // ---- Console layout ----------------------------------------------------
    readonly property bool _consoleVisible: !QGroundControl.videoManager.fullScreen
    readonly property real _u:              MLTheme.u
    // side panel widths: saved by the operator (drag the inner edge), limited to the window
    readonly property real _leftW:          Math.round(Math.max(300 * _u, Math.min(MLState.leftWidth * _u, width * 0.34)))
    readonly property real _rightW:         Math.round(Math.max(300 * _u, Math.min(MLState.rightWidth * _u, width * 0.34)))
    readonly property real _profileH:       height > 900 * _u ? 176 * _u : 132 * _u
    readonly property real _gap:            Math.round(ScreenTools.defaultFontPixelWidth * 0.6)

    property real   _fullItemZorder:    0
    property real   _pipItemZorder:     QGroundControl.zOrderWidgets

    function _calcCenterViewPort() {
        var newToolInset = Qt.rect(0, 0, width, height)
        toolstrip.adjustToolInset(newToolInset)
    }

    function dropMainStatusIndicatorTool() {
        toolbar.dropMainStatusIndicatorTool();
    }

    QGCToolInsets {
        id:                     _toolInsets
        topEdgeLeftInset:       _consoleVisible ? 0 : toolbar.height
        topEdgeCenterInset:     topEdgeLeftInset
        topEdgeRightInset:      topEdgeLeftInset
        leftEdgeBottomInset:    _pipView.leftEdgeBottomInset
        bottomEdgeLeftInset:    _pipView.bottomEdgeLeftInset
    }

    Rectangle {
        anchors.fill:   parent
        z:              -2
        color:          MLTheme.bg
    }

    // ---- floating console panels over a full-window map ---------------------
    readonly property real _m: Math.round(10 * _u)

    // soft shadows under the floating panels
    MLPanelShadow { target: flightColumn }
    MLPanelShadow { target: systemsColumn }
    Item {
        x: dock.x; y: dock.y; width: dock.width; height: dock.height
        visible: dock.visible
        MLPanelShadow { target: fleetLanes }
        MLPanelShadow { target: commandBar }
    }

    MLSideDock {
        id:                 flightColumn
        side:               "left"
        anchors.top:        toolbar.bottom
        anchors.topMargin:  _m
        anchors.bottom:     dock.top
        anchors.bottomMargin: _m
        anchors.left:       parent.left
        anchors.leftMargin: _m
        open:               _consoleVisible && MLState.leftOpen && !MLState.leftDetached
        openWidth:          _leftW
        detachable:         MLState.isAdvanced
        onDetachRequested:  MLState.leftDetached = true
        tabs:               MLState.isStandard ? [{ key: "ready", label: qsTr("비행 준비") }, { key: "flight", label: qsTr("비행 계기") }]
                                               : [{ key: "flight", label: qsTr("비행 계기") }, { key: "fleet", label: qsTr("편대 · 기체") }]
        current:            MLState.isStandard ? _stdLeftTab : MLState.leftTab
        onTabSelected:      (k) => { if (MLState.isStandard) _stdLeftTab = k; else { MLState.leftTab = k; MLState.markCustom() } }
        onCloseRequested:   { MLState.leftOpen = false; MLState.markCustom() }
        onWidthDragged:     (px) => { MLState.leftWidth = px / _u; MLState.markCustom() }

        MLFlightColumn {
            property string pageKey: "flight"
            color:          "transparent"
            clip:           true
        }
        MLFleetCards {
            property string pageKey: "fleet"
        }
        MLReadyPanel {
            property string pageKey: "ready"
        }
    }
    property string _stdLeftTab: "ready"

    MLSideDock {
        id:                 systemsColumn
        side:               "right"
        anchors.top:        toolbar.bottom
        anchors.topMargin:  _m
        anchors.bottom:     dock.top
        anchors.bottomMargin: _m
        anchors.right:      parent.right
        anchors.rightMargin: _m
        open:               _consoleVisible && !MLState.rightDetached && (MLState.isStandard ? MLState.acactDetailOpen : MLState.rightOpen)
        openWidth:          _rightW
        detachable:         MLState.isAdvanced
        onDetachRequested:  MLState.rightDetached = true
        tabs:               [{ key: "systems", label: qsTr("기체 시스템") }, { key: "acact", label: "ACACT" }]
        current:            MLState.isStandard ? _stdRightTab : MLState.rightTab
        onTabSelected:      (k) => { if (MLState.isStandard) _stdRightTab = k; else { MLState.rightTab = k; MLState.markCustom() } }
        onCloseRequested:   { if (MLState.isStandard) MLState.acactDetailOpen = false; else { MLState.rightOpen = false; MLState.markCustom() } }
        onWidthDragged:     (px) => { MLState.rightWidth = px / _u; MLState.markCustom() }

        MLSystemsColumn {
            property string pageKey: "systems"
            color:          "transparent"
            clip:           true
        }
        MLAcactPanel {
            property string pageKey: "acact"
        }
    }

    property string _stdRightTab: "acact"

    // side panels in their own windows (dual monitor); closing the window docks the panel again
    Loader {
        active: MLState.leftDetached
        sourceComponent: Component {
            Window {
                visible:    true
                width:      460 * _u
                height:     980 * _u
                title:      "MobilityLab GCS — " + qsTr("비행 계기 · 편대")
                color:      MLTheme.bg
                onClosing:  MLState.leftDetached = false
                MLSideDock {
                    anchors.fill:   parent
                    anchors.margins: 6 * _u
                    openWidth:      parent.width - 12 * _u
                    tabs:           [{ key: "flight", label: qsTr("비행 계기") }, { key: "fleet", label: qsTr("편대 · 기체") }]
                    current:        MLState.leftTab
                    onTabSelected:  (k) => MLState.leftTab = k
                    onCloseRequested: MLState.leftDetached = false
                    MLFlightColumn { property string pageKey: "flight"; color: "transparent"; clip: true }
                    MLFleetCards { property string pageKey: "fleet" }
                }
            }
        }
    }
    Loader {
        active: MLState.rightDetached
        sourceComponent: Component {
            Window {
                visible:    true
                width:      460 * _u
                height:     980 * _u
                title:      "MobilityLab GCS — " + qsTr("기체 시스템 · ACACT")
                color:      MLTheme.bg
                onClosing:  MLState.rightDetached = false
                MLSideDock {
                    anchors.fill:   parent
                    anchors.margins: 6 * _u
                    side:           "right"
                    openWidth:      parent.width - 12 * _u
                    tabs:           [{ key: "systems", label: qsTr("기체 시스템") }, { key: "acact", label: "ACACT" }]
                    current:        MLState.rightTab
                    onTabSelected:  (k) => MLState.rightTab = k
                    onCloseRequested: MLState.rightDetached = false
                    MLSystemsColumn { property string pageKey: "systems"; color: "transparent"; clip: true }
                    MLAcactPanel { property string pageKey: "acact" }
                }
            }
        }
    }

    // re-open tabs on the screen edges when a side panel is folded away
    MLEdgeTab {
        anchors.left:           parent.left
        anchors.verticalCenter: flightColumn.verticalCenter
        visible:                _consoleVisible && !MLState.leftOpen && !MLState.leftDetached
        side:                   "left"
        text:                   qsTr("계기 · 편대")
        onClicked:              { MLState.leftOpen = true; MLState.markCustom() }
    }
    MLEdgeTab {
        anchors.right:          parent.right
        anchors.verticalCenter: systemsColumn.verticalCenter
        visible:                _consoleVisible && MLState.isAdvanced && !MLState.rightOpen && !MLState.rightDetached
        side:                   "right"
        text:                   qsTr("시스템 · ACACT")
        onClicked:              { MLState.rightOpen = true; MLState.markCustom() }
    }

    // bottom dock: fleet lanes (+ ACACT Guard) and the command bar
    Column {
        id:                 dock
        anchors.left:       parent.left
        anchors.right:      parent.right
        anchors.bottom:     parent.bottom
        anchors.margins:    _m
        spacing:            _m
        visible:            _consoleVisible

        MLFleetLanes {
            id:      fleetLanes
            width:   parent.width
            height:  implicitHeight
            visible: MLState.dockOpen && MLState.isAdvanced
        }
        MLCommandBar {
            id:             commandBar
            width:          parent.width
            height:         implicitHeight
            leftWidth:      _leftW
            rightWidth:     _rightW
            color:          MLTheme.glassStrong
            radius:         MLTheme.panelRadius
            border.color:   MLTheme.glassEdge
        }
    }

    // Fleet (group) commands, opened from the top bar
    MLFleetPanel {
        id:                 fleetPanel
        anchors.top:        toolbar.bottom
        anchors.left:       flightColumn.right
        anchors.margins:    _gap * 2
        width:              Math.min(520 * _u, mapHolder.width - _gap * 4)
        height:             Math.min(implicitHeight, mapHolder.height - _gap * 4)
        z:                  QGroundControl.zOrderTopMost
        visible:            _consoleVisible && MLState.fleetOpen && QGroundControl.multiVehicleManager.vehicles.count > 1
    }

    // Non-blocking notice when another vehicle connects / disconnects
    MLToast {
        id:                         toast
        anchors.top:                toolbar.bottom
        anchors.topMargin:          _gap * 3
        anchors.horizontalCenter:   mapHolder.horizontalCenter
        z:                          QGroundControl.zOrderTopMost + 1
    }
    Connections {
        target: QGroundControl.multiVehicleManager
        function onVehicleAdded(vehicle) {
            if (typeof mlTestAcact !== "undefined" && mlTestAcact) console.log("MLVEHICLE added " + vehicle.id)
            // a real aircraft appeared: the presentation screen has no flight controls, so leave it
            if (MLState.isShowcase && !(typeof mlDemo !== "undefined" && mlDemo.active && mlDemo.isDemoSysid(vehicle.id))) {
                MLState.leaveShowcase()
                toast.show(qsTr("실기체 UAV %1 연결 — 시연 화면을 닫고 관제 화면으로 돌아왔습니다").arg(("0" + vehicle.id).slice(-2)), MLTheme.caution)
            }
            if (QGroundControl.multiVehicleManager.vehicles.count > 1) {
                toast.show(qsTr("UAV %1 연결됨 · 위쪽 탭에서 선택하세요").arg(("0" + vehicle.id).slice(-2)), MLTheme.ok)
            }
        }
        function onVehicleRemoved(vehicle) {
            toast.show(qsTr("UAV %1 연결 끊김").arg(("0" + vehicle.id).slice(-2)), MLTheme.caution)
        }
    }

    // operating mode changes: logged, and a refused change is explained
    Connections {
        target: MLState
        function onModeRefused(mode, reason) {
            toast.show(reason, MLTheme.caution)
            if (typeof mlTestAcact !== "undefined" && mlTestAcact) console.log("MLMODE refused " + mode)
        }
        function onUiModeChanged() {
            MLState.log(qsTr("화면 모드 → %1").arg(MLState.uiMode.toUpperCase()), 0, 0, "GCS")
            if (typeof mlTestAcact !== "undefined" && mlTestAcact) console.log("MLMODE " + MLState.uiMode)
        }
    }

    // ML_PERF=1: frame rate, console-ready time and screen-mode switch times into the log (tools/perf_run.py)
    Item {
        visible: false
        property int frames: 0
        property double modeT0: 0
        Connections {
            target: typeof mlPerf !== "undefined" && mlPerf && typeof mainWindow !== "undefined" ? mainWindow : null
            function onFrameSwapped() {
                parent.frames++
                if (parent.modeT0 > 0) { console.log("MLPERF mode " + MLState.uiMode + " " + (Date.now() - parent.modeT0) + " ms"); parent.modeT0 = 0 }
            }
        }
        Timer {
            interval: 5000; repeat: true; running: typeof mlPerf !== "undefined" && mlPerf
            onTriggered: { console.log("MLPERF fps " + (parent.frames / 5).toFixed(1)); parent.frames = 0 }
        }
        Timer {
            interval: 10000; repeat: true; running: typeof mlPerfModes !== "undefined" && mlPerfModes
            property int n: 0
            onTriggered: { parent.modeT0 = Date.now(); MLState.setUiMode(n % 2 === 0 ? "advanced" : "standard"); n++ }
        }
        Connections {
            target: MLState
            function onBootDoneChanged() {
                if (MLState.bootDone && typeof mlPerf !== "undefined" && mlPerf) console.log("MLPERF ready")
                // the previous run did not end normally (crash, power loss, killed): say so once
                if (MLState.bootDone && typeof mlSystem !== "undefined" && mlSystem.previousCrash) {
                    toast.show(qsTr("이전 실행이 정상 종료되지 않았습니다 — 비행 기록은 보존됩니다. 환경 설정에서 진단 보고서를 만들 수 있습니다"), MLTheme.caution)
                    MLState.log(qsTr("이전 실행 비정상 종료 감지"), 1, 0, "GCS")
                }
            }
        }
    }

    // keyboard shortcuts (no flight commands — see MLShortcuts)
    MLShortcuts { id: mlShortcuts; window: typeof mainWindow !== "undefined" ? mainWindow : null }

    // SITL test hook (ML_TEST_UI_MODES=1): switch the screen mode every few seconds during a flight;
    // the flight result must be unaffected (tools/ci_sitl.sh case "modes")
    Timer {
        interval: 4000; repeat: true
        running: typeof mlTestUiModes !== "undefined" && mlTestUiModes
        property int n: 0
        onTriggered: { var seq = ["advanced", "showcase", "standard"]; MLState.setUiMode(seq[n % 3]); n++ }
    }

    // ---- Event log feed: FC messages, mode / arming changes -----------------
    Instantiator {
        model: QGroundControl.multiVehicleManager.vehicles
        delegate: QtObject {
            required property var object
            readonly property var _v: object
            property var _conn: Connections {
                target: _v
                function onTextMessageReceived(sysid, componentid, severity, text, description) {
                    if (severity >= 7) return
                    MLState.log(text, severity <= 3 ? 3 : (severity === 4 ? 2 : 0), sysid, "FC")
                }
                function onFlightModeChanged(mode) { MLState.log(qsTr("비행 모드 → %1").arg(mode), 0, _v.id, "FC") }
                function onArmedChanged(armed) { MLState.log(armed ? qsTr("시동 걸림") : qsTr("시동 꺼짐"), 1, _v.id, "FC") }
            }
            Component.onCompleted: MLState.log(qsTr("UAV %1 연결 · %2").arg(("0" + _v.id).slice(-2)).arg(MLTheme.vehicleTypeName(_v)), 1, _v.id, "GCS")
        }
    }

    // ACACT (built-in guard, MLAcactRuntime) events into the same event log
    Connections {
        target: typeof mlGuard !== "undefined" ? mlGuard : null
        function onGuardEvent(seq, time, who, text) {
            var m = /^D(\d+)$/.exec(who)
            var level = /긴급|두절|끊김|오류|실패|※|emergency|lost|error|fail|danger/i.test(text) ? 3
                      : (/회피|위험|개입|HOLD|우선|avoid|interven|operator/i.test(text) ? 2 : (/완료|시작|복귀|done|start|back to/i.test(text) ? 1 : 0))
            MLState.log("ACACT · " + (m ? "" : who + " · ") + text, level, m ? Number(m[1]) : 0, "ACACT")
            if (typeof mlTestAcact !== "undefined" && mlTestAcact) console.log("MLACACT " + who + " | " + text)
        }
    }

    // screen-capture tour (ML_TOUR=1, tools/ui_tour.sh)
    Loader {
        active: typeof mlTour !== "undefined" && mlTour
        sourceComponent: Component { MLTourDriver { } }
    }

    // SITL tests (ML_TEST_ACACT=1): operator-workflow driver, see MLAcactTestDriver.qml
    Loader {
        active: typeof mlTestAcact !== "undefined" && mlTestAcact
        sourceComponent: Component {
            MLAcactTestDriver {
                testCase: mlTestAcactCase
                planDir:  mlTestPlanDir
                n:        mlTestAcactN
                _openConsole: function() { MLState.guardConsoleOpen = true }
            }
        }
    }

    // map requests from the panels (fleet cards, map tools)
    Connections {
        target: MLState
        function onFitAllRequested() {
            var vs = QGroundControl.multiVehicleManager.vehicles
            var pts = []
            for (var i = 0; i < vs.count; i++) {
                var c = vs.get(i).coordinate
                if (c && c.isValid) pts.push(c)
            }
            if (pts.length === 0) return
            if (pts.length === 1) { mapControl.center = pts[0]; return }
            var n = -90, s = 90, e = -180, w = 180
            for (var k = 0; k < pts.length; k++) {
                n = Math.max(n, pts[k].latitude); s = Math.min(s, pts[k].latitude)
                e = Math.max(e, pts[k].longitude); w = Math.min(w, pts[k].longitude)
            }
            // margin: 25 % of the span, at least ~40 m
            var dLat = Math.max((n - s) * 0.25, 0.0004), dLon = Math.max((e - w) * 0.25, 0.0005)
            mapControl.setVisibleRegion(QtPositioning.rectangle(QtPositioning.coordinate(n + dLat, w - dLon), QtPositioning.coordinate(s - dLat, e + dLon)))
        }
        function onCenterRequested(coordinate) {
            if (coordinate && coordinate.isValid) mapControl.center = coordinate
        }
    }

    Component.onCompleted: {
        mainWindow.criticalVehicleMessageHandler = function(message) { alertBanner.push(message) }
    }
    Component.onDestruction: mainWindow.criticalVehicleMessageHandler = null

    // Map (and video) fill the window under the floating panels
    Item {
        id:                 mapLayer
        z:                  -1
        anchors.top:        _consoleVisible ? toolbar.bottom : parent.top
        anchors.bottom:     parent.bottom
        anchors.left:       parent.left
        anchors.right:      parent.right

        FlyViewMap {
            id:                     mapControl
            planMasterController:   _planController
            rightPanelWidth:        ScreenTools.defaultFontPixelHeight * 9
            pipView:                _pipView
            pipMode:                !_mainWindowIsMap
            toolInsets:             _mapInsets
            mapName:                "FlightDisplayView"
            enabled:                !_is3DMode
            visible:                !_is3DMode
        }

        FlyViewVideo {
            id:         videoControl
            pipView:    _pipView
        }

        PipView {
            id:                     _pipView
            anchors.left:           parent.left
            anchors.bottom:         parent.bottom
            anchors.leftMargin:     _consoleVisible ? flightColumn.width + _m * 2 : _toolsMargin
            anchors.bottomMargin:   _consoleVisible ? dock.height + _m * 2 : _toolsMargin
            item1IsFullSettingsKey: "MainFlyWindowIsMap"
            item1:                  mapControl
            item2:                  QGroundControl.videoManager.hasVideo ? videoControl : null
            show:                   QGroundControl.videoManager.hasVideo && !QGroundControl.videoManager.fullScreen &&
                                        (videoControl.pipState.state === videoControl.pipState.pipState || mapControl.pipState.state === mapControl.pipState.pipState)
            z:                      QGroundControl.zOrderWidgets

            property real leftEdgeBottomInset: visible ? width + _toolsMargin : 0
            property real bottomEdgeLeftInset: visible ? height + _toolsMargin : 0
        }

        Loader {
            id:           viewer3DLoader
            z:            1
            anchors.fill: parent
            visible:      _is3DMode
        }

        // ACACT Guard overlay (safety rings, pair distances, avoiding drones)
        MLGuardMapLayer {
            map: mapControl
        }

        // soft edge so the floating panels lift off the map
        Rectangle {
            anchors.fill:   parent
            visible:        _consoleVisible
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0;  color: String(MLTheme.alpha(MLTheme.bg, 0.6)) }
                GradientStop { position: 0.22; color: String(MLTheme.alpha(MLTheme.bg, 0)) }
                GradientStop { position: 0.78; color: String(MLTheme.alpha(MLTheme.bg, 0)) }
                GradientStop { position: 1.0;  color: String(MLTheme.alpha(MLTheme.bg, 0.6)) }
            }
        }
    }

    // Insets of the map area the operator can actually see (between the panels)
    QGCToolInsets {
        id:                     _mapInsets
        readonly property real _l: _consoleVisible ? mapHolder.x - mapLayer.x : 0
        readonly property real _r: _consoleVisible ? mapLayer.width - (mapHolder.x - mapLayer.x) - mapHolder.width : 0
        readonly property real _t: _consoleVisible ? mapHolder.y - mapLayer.y : 0
        readonly property real _b: _consoleVisible ? mapLayer.height - (mapHolder.y - mapLayer.y) - mapHolder.height : 0
        leftEdgeCenterInset:    _l + customOverlay.totalToolInsets.leftEdgeCenterInset
        leftEdgeTopInset:       _l + customOverlay.totalToolInsets.leftEdgeTopInset
        leftEdgeBottomInset:    _l + customOverlay.totalToolInsets.leftEdgeBottomInset
        rightEdgeCenterInset:   _r + customOverlay.totalToolInsets.rightEdgeCenterInset
        rightEdgeTopInset:      _r + customOverlay.totalToolInsets.rightEdgeTopInset
        rightEdgeBottomInset:   _r + customOverlay.totalToolInsets.rightEdgeBottomInset
        topEdgeCenterInset:     _t + customOverlay.totalToolInsets.topEdgeCenterInset
        topEdgeLeftInset:       _t + customOverlay.totalToolInsets.topEdgeLeftInset
        topEdgeRightInset:      _t + customOverlay.totalToolInsets.topEdgeRightInset
        bottomEdgeCenterInset:  _b + customOverlay.totalToolInsets.bottomEdgeCenterInset
        bottomEdgeLeftInset:    _b + customOverlay.totalToolInsets.bottomEdgeLeftInset
        bottomEdgeRightInset:   _b + customOverlay.totalToolInsets.bottomEdgeRightInset
    }

    // Visible map region: widgets, banners and the 목표 조정 panel live here
    Item {
        id:                 mapHolder
        anchors.top:        _consoleVisible ? toolbar.bottom : parent.top
        anchors.topMargin:  _consoleVisible ? _m : 0
        anchors.bottom:     _consoleVisible ? dock.top : parent.bottom
        anchors.bottomMargin: _consoleVisible ? _m : 0
        anchors.left:       _consoleVisible ? flightColumn.right : parent.left
        anchors.leftMargin: _consoleVisible ? _m : 0
        anchors.right:      _consoleVisible ? systemsColumn.left : parent.right
        anchors.rightMargin: _consoleVisible ? _m : 0

        // 고도 단면 (mission altitude profile), toggled from the map
        MLProfile {
            id:                 profile
            anchors.left:       parent.left
            anchors.right:      parent.right
            anchors.bottom:     parent.bottom
            height:             _profileH
            visible:            _consoleVisible && MLState.profileOpen
            z:                  QGroundControl.zOrderWidgets + 1
            color:              MLTheme.glass
            radius:             MLTheme.panelRadius
            border.color:       MLTheme.glassEdge
        }
        Rectangle {
            id:                 profileToggle
            anchors.right:      parent.right
            anchors.bottom:     profile.visible ? profile.top : parent.bottom
            anchors.bottomMargin: profile.visible ? _m : 0
            z:                  QGroundControl.zOrderWidgets + 1
            visible:            _consoleVisible
            width:              ptText.implicitWidth + 24 * _u
            height:             30 * _u
            radius:             15 * _u
            color:              MLState.profileOpen ? String(MLTheme.glass) : MLTheme.glass
            border.color:       MLState.profileOpen ? MLTheme.accent : MLTheme.glassEdge
            MLText { id: ptText; anchors.centerIn: parent; text: MLState.profileOpen ? qsTr("고도 단면 닫기") : qsTr("고도 단면"); font.pixelSize: MLTheme.fsSmall; color: MLState.profileOpen ? MLTheme.accent : MLTheme.label }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: MLState.profileOpen = !MLState.profileOpen }
        }




        FlyViewWidgetLayer {
            id:                     widgetLayer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _widgetMargin
            anchors.topMargin:      (_consoleVisible ? 0 : toolbar.height) + _widgetMargin
            z:                      _fullItemZorder + 2
            parentToolInsets:       _toolInsets
            mapControl:             _mapControl
            viewer3DCameraController: viewer3DLoader.item ? viewer3DLoader.item.cameraController : null
            visible:                !QGroundControl.videoManager.fullScreen
        }

        FlyViewCustomLayer {
            id:                 customOverlay
            anchors.fill:       widgetLayer
            z:                  _fullItemZorder + 2
            parentToolInsets:   widgetLayer.totalToolInsets
            mapControl:         _mapControl
            visible:            !QGroundControl.videoManager.fullScreen
        }

        // Development tool for visualizing the insets for a paticular layer, show if needed
        FlyViewInsetViewer {
            id:                     widgetLayerInsetViewer
            anchors.top:            parent.top
            anchors.bottom:         parent.bottom
            anchors.left:           parent.left
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            z:                      widgetLayer.z + 1
            insetsToView:           widgetLayer.totalToolInsets
            visible:                false
        }

        GuidedActionsController {
            id:                 guidedActionsController
            missionController:  _missionController
            guidedValueSlider:     _guidedValueSlider
        }

        //-- Guided value slider (e.g. altitude)
        GuidedValueSlider {
            id:                 guidedValueSlider
            anchors.right:      parent.right
            anchors.top:        parent.top
            anchors.bottom:     parent.bottom
            anchors.topMargin:  _consoleVisible ? 0 : toolbar.height
            z:                  QGroundControl.zOrderTopMost
            visible:            false
        }

        // 목표 조정 (heading / altitude / speed), opened from the command bar
        MLSetpointPanel {
            id:                 setpointPanel
            anchors.left:       parent.left
            anchors.bottom:     profile.visible ? profile.top : parent.bottom
            anchors.leftMargin: _gap * 2
            anchors.bottomMargin: profile.visible ? _m : _gap * 2
            z:                  QGroundControl.zOrderTopMost
            visible:            MLState.setpointsOpen || (typeof mlTestSetpoints !== "undefined" && mlTestSetpoints)
            onCloseRequested:   MLState.setpointsOpen = false
        }

        // ACACT 가드 콘솔 (start / stop / scenario / commands / terminal)
        MLGuardConsole {
            anchors.top:            parent.top
            anchors.right:          parent.right
            anchors.bottom:         parent.bottom
            anchors.margins:        _gap * 2
            width:                  Math.min(implicitWidth, parent.width - _gap * 4)
            z:                      QGroundControl.zOrderTopMost
            visible:                _consoleVisible && MLState.guardConsoleOpen && !MLState.consoleDetached
            detachable:             true
            onCloseRequested:       MLState.guardConsoleOpen = false
            onDetachRequested:      MLState.consoleDetached = true
        }
        // the same console in its own window (second monitor)
        Loader {
            active: MLState.guardConsoleOpen && MLState.consoleDetached
            sourceComponent: Component {
                Window {
                    visible:    true
                    width:      640 * _u
                    height:     900 * _u
                    title:      "MobilityLab GCS — ACACT"
                    color:      MLTheme.bg
                    onClosing:  MLState.consoleDetached = false
                    MLGuardConsole {
                        anchors.fill:       parent
                        anchors.margins:    6 * _u
                        detachable:         false
                        attachable:         true
                        onCloseRequested:   { MLState.consoleDetached = false; MLState.guardConsoleOpen = false }
                        onAttachRequested:  MLState.consoleDetached = false
                    }
                }
            }
        }

        // 비행 분석 · 리플레이 (guard logs, PDF report)
        Loader {
            anchors.fill:       parent
            anchors.margins:    _gap * 2
            z:                  QGroundControl.zOrderTopMost + 1
            active:             MLState.analysisOpen && !MLState.analysisDetached && typeof mlAnalysis !== "undefined"
            visible:            active
            sourceComponent: Component {
                MLAnalysisView {
                    detachable:         true
                    onCloseRequested:   MLState.analysisOpen = false
                    onDetachRequested:  MLState.analysisDetached = true
                }
            }
        }
        Loader {
            active: MLState.analysisOpen && MLState.analysisDetached && typeof mlAnalysis !== "undefined"
            sourceComponent: Component {
                Window {
                    visible:    true
                    width:      1500 * _u
                    height:     900 * _u
                    title:      "MobilityLab GCS — " + qsTr("비행 분석")
                    color:      MLTheme.bg
                    onClosing:  { MLState.analysisDetached = false; MLState.analysisOpen = false }
                    MLAnalysisView {
                        anchors.fill:       parent
                        anchors.margins:    6 * _u
                        attachable:         true
                        onCloseRequested:   { MLState.analysisDetached = false; MLState.analysisOpen = false }
                        onAttachRequested:  MLState.analysisDetached = false
                    }
                }
            }
        }

        // Critical vehicle messages (replaces QGC's yellow popup)
        MLAlertBanner {
            id:                         alertBanner
            anchors.top:                parent.top
            anchors.topMargin:          _gap * 2
            anchors.horizontalCenter:   parent.horizontalCenter
            width:                      Math.min(720 * _u, parent.width - 360 * _u)
            z:                          QGroundControl.zOrderTopMost
        }

        // alert centre model (bell in the top bar) and the integrated pre-flight check
        MLAlertCenter { id: alertModel; Component.onCompleted: MLState.alertCenter = alertModel }
        MLPreflightView {
            anchors.fill:       parent
            anchors.margins:    _gap * 2
            z:                  QGroundControl.zOrderTopMost + 2
            visible:            _consoleVisible && MLState.preflightOpen
            onCloseRequested:   MLState.preflightOpen = false
        }

        // ACACT: run recorder (timeline data), event timeline, 3D situation view
        MLAcactRecorder { }
        MLAcactTimeline {
            id:                 acactTimeline
            anchors.left:       parent.left
            anchors.right:      parent.right
            anchors.bottom:     profile.visible ? profile.top : parent.bottom
            anchors.bottomMargin: profile.visible ? _m : 0
            height:             Math.min(300 * _u, parent.height * 0.42)
            z:                  QGroundControl.zOrderWidgets + 3
            visible:            _consoleVisible && MLState.acactTimelineOpen
            onCloseRequested:   MLState.acactTimelineOpen = false
        }
        Loader {
            anchors.left:       parent.left
            anchors.top:        parent.top
            anchors.topMargin:  60 * _u
            anchors.leftMargin: 70 * _u
            width:              Math.min(parent.width * 0.55, 900 * _u)
            height:             Math.min(parent.height - 80 * _u - (acactTimeline.visible ? acactTimeline.height : 0), 640 * _u)
            z:                  QGroundControl.zOrderWidgets + 4
            active:             _consoleVisible && MLState.acact3dOpen && !MLState.acact3dDetached
            sourceComponent: Component {
                MLAcact3D {
                    onCloseRequested:   MLState.acact3dOpen = false
                    onDetachRequested:  MLState.acact3dDetached = true
                }
            }
        }
        Loader {
            active: MLState.acact3dOpen && MLState.acact3dDetached
            sourceComponent: Component {
                Window {
                    visible:    true
                    width:      1100 * _u
                    height:     760 * _u
                    title:      "MobilityLab GCS — " + qsTr("ACACT 3D 상황도")
                    color:      MLTheme.bg
                    onClosing:  { MLState.acact3dDetached = false; MLState.acact3dOpen = false }
                    MLAcact3D {
                        anchors.fill:       parent
                        detachable:         false
                        onCloseRequested:   { MLState.acact3dDetached = false; MLState.acact3dOpen = false }
                    }
                }
            }
        }

        // selected-vehicle HUD over the map (instrument panel folded, or chosen in 화면 구성)
        MLVehicleHud {
            anchors.horizontalCenter:   parent.horizontalCenter
            anchors.bottom:             acactTimeline.visible ? acactTimeline.top : (profile.visible ? profile.top : parent.bottom)
            anchors.bottomMargin:       _gap * 2
            z:                          QGroundControl.zOrderWidgets + 2
            visible:                    _consoleVisible && !!_activeVehicle && !_is3DMode && (MLState.showVehicleHud || !MLState.leftOpen)
        }

        // built-in demo: banner (always while running) and the control panel
        MLDemoBanner {
            anchors.bottom:             parent.bottom
            anchors.bottomMargin:       _gap * 2
            anchors.left:               parent.left
            anchors.leftMargin:         _gap * 2
            z:                          QGroundControl.zOrderTopMost
        }
        MLDemoPanel {
            anchors.centerIn:   parent
            z:                  QGroundControl.zOrderTopMost + 3
            visible:            _consoleVisible && MLState.demoOpen
            onCloseRequested:   MLState.demoOpen = false
        }

        // STANDARD: ACACT at a glance, below the search bar
        MLAcactStrip {
            // top-left of the map: clear of the search bar and of QGC's centred confirm slider
            anchors.top:                parent.top
            anchors.topMargin:          58 * _u
            anchors.left:               parent.left
            anchors.leftMargin:         78 * _u
            width:                      Math.min(implicitWidth, parent.width * 0.62)
            z:                          QGroundControl.zOrderWidgets + 3
            visible:                    _consoleVisible && MLState.isStandard && (QGroundControl.multiVehicleManager.vehicles.count > 1 || (typeof mlGuard !== "undefined" && mlGuard.active))
        }

        // map tools: search, favourites, measurement, provider, fit / centre / follow, server state
        MLMapTools {
            anchors.fill:   parent
            z:              QGroundControl.zOrderWidgets + 1
            map:            mapControl
            visible:        _consoleVisible && !_is3DMode
            rightInset:     guidedValueSlider.visible ? guidedValueSlider.width : 0
        }

        // Position readout
        MLMapHud {
            anchors.top:            parent.top
            anchors.right:          guidedValueSlider.visible ? guidedValueSlider.left : parent.right
            anchors.margins:        _gap * 2
            z:                      QGroundControl.zOrderWidgets
            visible:                _consoleVisible && !!_activeVehicle && !_is3DMode && MLState.showPositionHud
        }



        Connections {
            target: QGCViewer3DManager
            function onDisplayModeChanged() {
                if (QGCViewer3DManager.displayMode === QGCViewer3DManager.View3D) {
                    if (!viewer3DLoader.item) {
                        viewer3DLoader.setSource("qrc:/qml/QGroundControl/Viewer3D/Models3D/Viewer3DModel.qml")
                    }
                } else if (!_keepSceneAlive) {
                    viewer3DLoader.source = ""
                }
            }
        }
    }

    // first-run guide, preferences: centred over everything, with a scrim
    Rectangle {
        anchors.fill:   parent
        z:              QGroundControl.zOrderTopMost + 50
        visible:        MLState.onboardingOpen || MLState.prefsOpen
        color:          MLTheme.scrim
        MouseArea { anchors.fill: parent; onClicked: { MLState.prefsOpen = false; MLState.onboardingOpen = false } }
        MLOnboarding {
            anchors.centerIn: parent
            visible:          MLState.onboardingOpen
            onCloseRequested: MLState.onboardingOpen = false
            MouseArea { anchors.fill: parent; z: -1 }
        }
        Loader {
            anchors.centerIn: parent
            width:            Math.min(760 * _u, parent.width - 40 * _u)
            height:           Math.min(880 * _u, parent.height - 40 * _u)
            active:           MLState.prefsOpen
            sourceComponent:  Component {
                MLPrefsMenu {
                    shortcuts:        mlShortcuts
                    onCloseRequested: MLState.prefsOpen = false
                    MouseArea { anchors.fill: parent; z: -1 }
                }
            }
        }
    }
    // first start: open the guide once the start screen is gone (STANDARD, nothing connected yet)
    Connections {
        target: MLState
        function onBootDoneChanged() {
            if (MLState.bootDone && !MLState.onboardingDone && MLState.isStandard && !(typeof mlNoOnboarding !== "undefined" && mlNoOnboarding) && QGroundControl.multiVehicleManager.vehicles.count === 0
                    && !(typeof mlTour !== "undefined" && mlTour) && !(typeof mlTestAcact !== "undefined" && mlTestAcact) && !(typeof mlDemoAuto !== "undefined" && mlDemoAuto))
                MLState.onboardingOpen = true
        }
    }

    // v1.2 flight records over the console (below the toolbar so alerts stay visible)
    Loader {
        anchors.fill:   parent
        anchors.topMargin: toolbar.height
        z:              QGroundControl.zOrderTopMost + 30
        active:         MLState.recordsOpen
        sourceComponent: Component { MLRecordsView { onCloseRequested: MLState.recordsOpen = false } }
    }

    // SHOWCASE: the presentation screen over the whole window (the console underneath keeps running)
    Loader {
        anchors.fill:   parent
        z:              QGroundControl.zOrderTopMost + 40
        active:         MLState.isShowcase
        sourceComponent: Component {
            MLShowcaseView {
                onExitRequested:       MLState.leaveShowcase()
                onFullscreenRequested: mlShortcuts.run("view.full")
            }
        }
    }

    FlyViewToolBar {
        id:                 toolbar
        leftWidth:          _leftW + _m
        guidedValueSlider:  _guidedValueSlider
        visible:            !QGroundControl.videoManager.fullScreen
    }

    // MOBILITY LAB start screen (real start-up state), fades out by itself
    Loader {
        anchors.fill:   parent
        z:              QGroundControl.zOrderTopMost + 100
        active:         !MLState.bootDone
        sourceComponent: Component { MLBootScreen { } }
    }
}
